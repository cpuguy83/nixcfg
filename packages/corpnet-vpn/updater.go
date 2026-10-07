package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"
)

const (
	clientID      = "d7b530a4-7680-4c23-a8bf-c52c121d2e87"
	redirectURI   = "https://login.microsoftonline.com/common/oauth2/nativeclient"
	sharepoint    = "microsoft.sharepoint.com"
	site          = "/sites/Network_Connectivity"
	profile       = "MSFT-AzVPN-Manual.xml"
	candidatePath = "/run/corpnet-profile-update/policy.json"
	maxBytes      = 8 * 1024 * 1024
)

type commandRunner func(args []string, stage string, env map[string]string, input string) (string, error)

var aadErrorPattern = regexp.MustCompile(`AADSTS[0-9]+`)

func runCommand(args []string, stage string, env map[string]string, input string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, args[0], args[1:]...)

	if env != nil {
		cmd.Env = envList(env)
	}

	cmd.Stdin = strings.NewReader(input)
	var stderr strings.Builder
	cmd.Stderr = &stderr

	stdout, err := cmd.Output()

	if ctx.Err() != nil {
		return "", fmt.Errorf("%s: timed out", stage)
	}

	if err != nil {
		var exit *exec.ExitError

		if errors.As(err, &exit) {
			codes := aadErrorPattern.FindAllString(stderr.String(), -1)
			slices.Sort(codes)
			codes = slices.Compact(codes)

			detail := ""
			if len(codes) != 0 {
				detail = "; " + strings.Join(codes, ", ")
			}

			return "", fmt.Errorf("%s: failed (exit %d%s)", stage, exit.ExitCode(), detail)
		}

		return "", fmt.Errorf("%s: system operation failed", stage)
	}

	return string(stdout), nil
}

type updater struct {
	run       commandRunner
	client    *http.Client
	policy    string
	candidate string
	euid      int
	now       func() time.Time
	output    io.Writer
}

func newUpdater(output io.Writer) *updater {
	return &updater{
		run: runCommand,
		client: &http.Client{
			Transport: &http.Transport{Proxy: nil, DisableCompression: true},
			CheckRedirect: func(*http.Request, []*http.Request) error {
				return http.ErrUseLastResponse
			},
			Timeout: 30 * time.Second,
		},
		policy:    policyPath,
		candidate: candidatePath,
		euid:      os.Geteuid(),
		now:       time.Now,
		output:    output,
	}
}

var sessionPattern = regexp.MustCompile(`^[a-zA-Z0-9]+$`)

func (u *updater) signedIn(uid int) (bool, error) {
	output, err := u.run([]string{"loginctl", "list-sessions", "--json=short", "--no-pager"},
		"session discovery", nil, "")
	if err != nil {
		return false, err
	}

	value, err := decodeJSON([]byte(output), "session discovery")
	if err != nil {
		return false, err
	}

	rows, ok := value.([]any)
	if !ok {
		return false, fmt.Errorf("session discovery: invalid session list")
	}

	for _, value := range rows {
		if _, ok := value.(map[string]any); !ok {
			return false, fmt.Errorf("session discovery: invalid session list")
		}
	}

	for _, value := range rows {
		row := value.(map[string]any)
		if row["uid"] != json.Number(strconv.Itoa(uid)) || row["class"] != "user" {
			continue
		}

		session, ok := row["session"].(string)
		if !ok || !sessionPattern.MatchString(session) {
			return false, fmt.Errorf("session discovery: invalid session identifier")
		}

		output, err := u.run([]string{
			"loginctl", "show-session", "--no-pager", "--property=User",
			"--property=Class", "--property=State", session,
		}, "session status", nil, "")
		if err != nil {
			return false, err
		}

		properties := make(map[string]string)

		for _, line := range strings.Split(output, "\n") {
			if key, value, ok := strings.Cut(line, "="); ok {
				properties[key] = value
			}
		}

		if properties["User"] == strconv.Itoa(uid) && properties["Class"] == "user" &&
			(properties["State"] == "active" || properties["State"] == "online") {
			return true, nil
		}
	}

	return false, nil
}

func (u *updater) eligible(uid int) (bool, error) {
	signedIn, err := u.signedIn(uid)
	if err != nil {
		return false, err
	}

	if !signedIn {
		fmt.Fprintln(u.output, "corpnet-vpn: skipped; no signed-in user session")

		return false, nil
	}

	info, err := os.Stat(u.policy)
	if os.IsNotExist(err) {
		return true, nil
	}

	if err != nil {
		return false, err
	}

	due, err := policyDue(info, u.now())
	if err != nil {
		return false, err
	}

	if !due {
		fmt.Fprintln(u.output, "corpnet-vpn: skipped; saved policy is already fresh today")
	}

	return due, nil
}

func policyDue(info os.FileInfo, now time.Time) (bool, error) {
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || stat.Uid != 0 || !info.Mode().IsRegular() {
		return false, fmt.Errorf("saved policy is not a root-owned regular file")
	}

	y, m, d := info.ModTime().In(time.Local).Date()

	ny, nm, nd := now.In(time.Local).Date()

	return y != ny || m != nm || d != nd, nil
}

func (u *updater) broker(method string, request map[string]any, uid int, correlation string) (map[string]any, error) {
	env := environment()

	env["XDG_RUNTIME_DIR"] = fmt.Sprintf("/run/user/%d", uid)

	env["DBUS_SESSION_BUS_ADDRESS"] = fmt.Sprintf("unix:path=/run/user/%d/bus", uid)

	payload, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("broker: invalid request")
	}

	raw, err := u.run([]string{
		"busctl", "--user", "--json=short", "call",
		"com.microsoft.identity.broker1", "/com/microsoft/identity/broker1",
		"com.microsoft.identity.Broker1", method, "sss", "0.0", correlation, string(payload),
	}, "broker "+method, env, "")
	if err != nil {
		return nil, err
	}

	value, err := decodeJSON([]byte(raw), "broker envelope")
	if err != nil {
		return nil, err
	}

	envelope, ok := value.(map[string]any)
	if !ok || envelope["type"] != "s" {
		return nil, fmt.Errorf("broker: invalid response envelope")
	}

	data, ok := stringList(envelope["data"])
	if !ok || len(data) != 1 {
		return nil, fmt.Errorf("broker: invalid response envelope")
	}

	value, err = decodeJSON([]byte(data[0]), "broker response")
	if err != nil {
		return nil, err
	}

	response, ok := value.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("broker: invalid response")
	}

	if truthy(response["error"]) {
		return nil, fmt.Errorf("broker %s: authentication unavailable; sign-in may need refreshing", method)
	}

	return response, nil
}

func truthy(value any) bool {
	switch value := value.(type) {
	case nil:
		return false

	case bool:
		return value

	case string:
		return value != ""

	case []any:
		return len(value) != 0

	case map[string]any:
		return len(value) != 0

	case json.Number:
		n, err := value.Float64()

		return err != nil || n != 0

	default:
		return true
	}
}

func uuidString(value string) (string, error) {
	value = strings.TrimPrefix(value, "urn:")

	value = strings.TrimPrefix(value, "uuid:")

	value = strings.Trim(value, "{}")

	value = strings.ReplaceAll(value, "-", "")

	decoded, err := hex.DecodeString(value)
	if err != nil || len(decoded) != 16 {
		return "", fmt.Errorf("broker: invalid account tenant")
	}

	return formatUUID(decoded), nil
}

func formatUUID(value []byte) string {
	return fmt.Sprintf("%x-%x-%x-%x-%x", value[:4], value[4:6], value[6:8], value[8:10], value[10:])
}

func (u *updater) accessToken(uid int, upn string) (string, error) {
	var id [16]byte

	if _, err := rand.Read(id[:]); err != nil {
		return "", fmt.Errorf("broker: correlation ID generation failed")
	}

	id[6] = id[6]&0x0f | 0x40
	id[8] = id[8]&0x3f | 0x80

	correlation := formatUUID(id[:])

	response, err := u.broker("getAccounts", map[string]any{
		"clientId": clientID, "redirectUri": redirectURI,
	}, uid, correlation)
	if err != nil {
		return "", err
	}

	accounts, ok := response["accounts"].([]any)
	if !ok {
		return "", fmt.Errorf("broker: invalid account list")
	}

	matches := make([]map[string]any, 0)

	for _, value := range accounts {
		account, ok := value.(map[string]any)
		if !ok {
			return "", fmt.Errorf("broker: invalid account list")
		}

		username, ok := account["username"].(string)
		if ok && strings.EqualFold(expandAccountFold(username), expandAccountFold(upn)) {
			matches = append(matches, account)
		}
	}

	if len(matches) != 1 {
		return "", fmt.Errorf("broker: expected exactly one configured account")
	}

	account := matches[0]
	tenant, _ := account["realm"].(string)

	realm, err := uuidString(tenant)
	if err != nil {
		return "", err
	}

	response, err = u.broker("acquireTokenSilently", map[string]any{"authParameters": map[string]any{
		"account": account, "username": account["username"],
		"authority":         "https://login.microsoftonline.com/" + realm,
		"authorizationType": 1, "clientId": clientID, "redirectUri": redirectURI,
		"requestedScopes": []string{"https://" + sharepoint + "/.default"},
	}}, uid, correlation)
	if err != nil {
		return "", err
	}

	tokenResponse, _ := response["brokerTokenResponse"].(map[string]any)
	token, ok := tokenResponse["accessToken"].(string)
	if !ok || token == "" || strings.ContainsAny(token, "\r\n") {
		return "", fmt.Errorf("broker: no usable access token")
	}

	return token, nil
}

// EqualFold handles single-rune folds but not the full Unicode expansions used
// by Python's casefold. Expand those first so account aliases remain ambiguous.
func expandAccountFold(value string) string {
	var result strings.Builder

	for _, r := range value {
		switch {
		case r >= '\u1f80' && r <= '\u1f8f':
			result.WriteRune('\u1f00' + (r-'\u1f80')%8)

			result.WriteRune('\u03b9')

		case r >= '\u1f90' && r <= '\u1f9f':
			result.WriteRune('\u1f20' + (r-'\u1f90')%8)

			result.WriteRune('\u03b9')

		case r >= '\u1fa0' && r <= '\u1faf':
			result.WriteRune('\u1f60' + (r-'\u1fa0')%8)

			result.WriteRune('\u03b9')

		default:
			if expansion, ok := accountFoldExpansions[r]; ok {
				result.WriteString(expansion)
			} else {
				result.WriteRune(r)
			}
		}
	}

	return result.String()
}

var accountFoldExpansions = map[rune]string{
	'\u00df': "ss",
	'\u0130': "i\u0307",
	'\u0149': "\u02bcn",
	'\u01f0': "j\u030c",
	'\u0390': "\u03b9\u0308\u0301",
	'\u03b0': "\u03c5\u0308\u0301",
	'\u0587': "\u0565\u0582",
	'\u1e96': "h\u0331",
	'\u1e97': "t\u0308",
	'\u1e98': "w\u030a",
	'\u1e99': "y\u030a",
	'\u1e9a': "a\u02be",
	'\u1e9e': "ss",
	'\u1f50': "\u03c5\u0313",
	'\u1f52': "\u03c5\u0313\u0300",
	'\u1f54': "\u03c5\u0313\u0301",
	'\u1f56': "\u03c5\u0313\u0342",
	'\u1fb2': "\u1f70\u03b9",
	'\u1fb3': "\u03b1\u03b9",
	'\u1fb4': "\u03ac\u03b9",
	'\u1fb6': "\u03b1\u0342",
	'\u1fb7': "\u03b1\u0342\u03b9",
	'\u1fbc': "\u03b1\u03b9",
	'\u1fc2': "\u1f74\u03b9",
	'\u1fc3': "\u03b7\u03b9",
	'\u1fc4': "\u03ae\u03b9",
	'\u1fc6': "\u03b7\u0342",
	'\u1fc7': "\u03b7\u0342\u03b9",
	'\u1fcc': "\u03b7\u03b9",
	'\u1fd2': "\u03b9\u0308\u0300",
	'\u1fd3': "\u03b9\u0308\u0301",
	'\u1fd6': "\u03b9\u0342",
	'\u1fd7': "\u03b9\u0308\u0342",
	'\u1fe2': "\u03c5\u0308\u0300",
	'\u1fe3': "\u03c5\u0308\u0301",
	'\u1fe4': "\u03c1\u0313",
	'\u1fe6': "\u03c5\u0342",
	'\u1fe7': "\u03c5\u0308\u0342",
	'\u1ff2': "\u1f7c\u03b9",
	'\u1ff3': "\u03c9\u03b9",
	'\u1ff4': "\u03ce\u03b9",
	'\u1ff6': "\u03c9\u0342",
	'\u1ff7': "\u03c9\u0342\u03b9",
	'\u1ffc': "\u03c9\u03b9",
	'\ufb00': "ff",
	'\ufb01': "fi",
	'\ufb02': "fl",
	'\ufb03': "ffi",
	'\ufb04': "ffl",
	'\ufb05': "st",
	'\ufb06': "st",
	'\ufb13': "\u0574\u0576",
	'\ufb14': "\u0574\u0565",
	'\ufb15': "\u0574\u056b",
	'\ufb16': "\u057e\u0576",
	'\ufb17': "\u0574\u056d",
}

func apiPath(location string) (string, error) {
	target, err := url.Parse(location)
	if err != nil {
		return "", fmt.Errorf("profile link: malformed destination")
	}

	if target.Scheme != "https" || !strings.EqualFold(target.Hostname(), sharepoint) ||
		target.User != nil || target.Fragment != "" || target.Opaque != "" {
		return "", fmt.Errorf("profile link: unexpected destination")
	}

	if port := target.Port(); port != "" {
		number, err := strconv.ParseUint(port, 10, 16)
		if err != nil || number != 443 {
			return "", fmt.Errorf("profile link: unexpected destination")
		}
	}
	// url.Parse has already decoded the path exactly once. Do not unescape it
	// again: encoded percent signs must fail the same validation as literal ones.
	path := target.Path
	if strings.HasPrefix(path, "/:u:/r/") {
		path = strings.TrimPrefix(path, "/:u:/r")
	}

	if !utf8.ValidString(path) || !strings.HasPrefix(path, site+"/") ||
		!strings.HasSuffix(path, "/"+profile) || strings.ContainsAny(path, "\\%") {
		return "", fmt.Errorf("profile link: unexpected file path")
	}

	for _, part := range strings.Split(path, "/")[1:] {
		if part == "" || part == "." || part == ".." {
			return "", fmt.Errorf("profile link: unexpected file path")
		}
	}

	for _, c := range path {
		if c < 32 {
			return "", fmt.Errorf("profile link: unexpected file path")
		}
	}

	var encoded strings.Builder

	for _, b := range []byte(strings.ReplaceAll(path, "'", "''")) {
		if (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') ||
			(b >= '0' && b <= '9') || strings.ContainsRune("/-_.~", rune(b)) {
			encoded.WriteByte(b)
		} else {
			fmt.Fprintf(&encoded, "%%%02X", b)
		}
	}

	return site + "/_api/web/GetFileByServerRelativePath(decodedUrl='" + encoded.String() + "')/$value", nil
}

func (u *updater) download(token string) (policy, error) {
	request, err := http.NewRequest(http.MethodGet, "https://aka.ms/AzVPN", nil)
	if err != nil {
		return policy{}, fmt.Errorf("profile link: request failed")
	}

	response, err := u.client.Do(request)
	if err != nil {
		return policy{}, fmt.Errorf("profile link: network operation failed")
	}

	response.Body.Close()

	location := response.Header.Get("Location")
	if !slices.Contains([]int{301, 302, 303, 307, 308}, response.StatusCode) || location == "" {
		return policy{}, fmt.Errorf("profile link: unexpected HTTP %d", response.StatusCode)
	}

	target, err := apiPath(location)
	if err != nil {
		return policy{}, err
	}

	request, err = http.NewRequest(http.MethodGet, "https://"+sharepoint+target, nil)
	if err != nil {
		return policy{}, fmt.Errorf("profile download: request failed")
	}

	request.Header.Set("Authorization", "Bearer "+token)

	request.Header.Set("Accept", "application/xml")

	response, err = u.client.Do(request)
	if err != nil {
		return policy{}, fmt.Errorf("profile download: network operation failed")
	}

	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		return policy{}, fmt.Errorf("profile download: HTTP %d; no redirect followed", response.StatusCode)
	}

	if strings.Contains(strings.ToLower(response.Header.Get("Content-Type")), "html") {
		return policy{}, fmt.Errorf("profile download: received HTML instead of XML")
	}

	content, err := io.ReadAll(io.LimitReader(response.Body, maxBytes+1))
	if err != nil {
		return policy{}, fmt.Errorf("profile download: response read failed")
	}

	if len(content) > maxBytes {
		return policy{}, fmt.Errorf("profile download: response exceeds 8 MiB")
	}

	return xmlPolicy(strings.NewReader(string(content)))
}

func (u *updater) fetch(uid int, upn string) error {
	if u.euid != uid || uid == 0 {
		return fmt.Errorf("fetch must run as the configured desktop user, not root")
	}

	signedIn, err := u.signedIn(uid)
	if err != nil {
		return err
	}

	if !signedIn {
		return fmt.Errorf("fetch cancelled; user is no longer signed in")
	}

	token, err := u.accessToken(uid, upn)
	if err != nil {
		return err
	}

	data, err := u.download(token)
	if err != nil {
		return err
	}

	if err := atomicJSON(u.candidate, data, 0600, false); err != nil {
		return err
	}

	fmt.Fprintf(u.output, "corpnet-vpn: fetched %d includes, %d excludes\n",
		len(data.Includes), len(data.Excludes))

	return nil
}

func (u *updater) install(uid int) error {
	if u.euid != 0 {
		return fmt.Errorf("install requires root")
	}

	signedIn, err := u.signedIn(uid)
	if err != nil {
		return err
	}

	if !signedIn {
		return fmt.Errorf("install cancelled; user is no longer signed in")
	}

	data, err := readCandidate(u.candidate, uid, maxBytes)
	if err != nil {
		return err
	}

	if err := atomicJSON(u.policy, data, 0644, true); err != nil {
		return err
	}

	fmt.Fprintf(u.output, "corpnet-vpn: installed %d includes, %d excludes; active routes unchanged\n",
		len(data.Includes), len(data.Excludes))

	return nil
}
