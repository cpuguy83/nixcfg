package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestSessions(t *testing.T) {
	t.Run("active and online user sessions qualify but lingering managers do not", func(t *testing.T) {
		for _, state := range []string{"active", "online", "closing"} {
			t.Run(state, func(t *testing.T) {
				u := newUpdater(io.Discard)
				calls := 0

				u.run = func(args []string, stage string, env map[string]string, input string) (string, error) {
					calls++

					if calls == 1 {
						requireEqual(t, args, []string{"loginctl", "list-sessions", "--json=short", "--no-pager"})

						return `[{"uid":1000,"class":"manager","session":"2"},{"uid":1000,"class":"user","session":"3"}]`, nil
					}

					requireEqual(t, args, []string{"loginctl", "show-session", "--no-pager",
						"--property=User", "--property=Class", "--property=State", "3"})

					return "User=1000\nClass=user\nState=" + state + "\n", nil
				}

				actual, err := u.signedIn(1000)
				requireNoError(t, err)

				requireEqual(t, actual, state != "closing")
				requireEqual(t, calls, 2)
			})
		}

		u := newUpdater(io.Discard)

		u.run = func(args []string, _ string, _ map[string]string, _ string) (string, error) {
			if args[1] != "list-sessions" {
				t.Fatal("queried a non-user or another user's session")
			}

			return `[{"uid":1000,"class":"manager","session":"2"},{"uid":1001,"class":"user","session":"4"}]`, nil
		}

		actual, err := u.signedIn(1000)
		requireNoError(t, err)

		requireEqual(t, actual, false)
	})

	t.Run("malformed discovery fails instead of being treated as logged out", func(t *testing.T) {
		for _, content := range []string{
			`invalid`, `{}`, `[null]`, `[{"uid":1000,"class":"user","session":"-unsafe"}]`,
			`[{"uid":1000,"class":"user","session":3}]`,
		} {
			u := newUpdater(io.Discard)

			u.run = func([]string, string, map[string]string, string) (string, error) {
				return content, nil
			}

			if _, err := u.signedIn(1000); err == nil {
				t.Fatal("accepted malformed session list")
			}
		}
	})

	t.Run("session properties must still identify the configured user", func(t *testing.T) {
		for _, properties := range []string{
			"User=1001\nClass=user\nState=active\n",
			"User=1000\nClass=manager\nState=active\n",
			"User=1000\nClass=user\n",
		} {
			u := newUpdater(io.Discard)

			u.run = func(args []string, _ string, _ map[string]string, _ string) (string, error) {
				if args[1] == "list-sessions" {
					return `[{"uid":1000,"class":"user","session":"3"}]`, nil
				}

				return properties, nil
			}

			actual, err := u.signedIn(1000)
			requireNoError(t, err)

			requireEqual(t, actual, false)
		}
	})
}

func TestEligibility(t *testing.T) {
	t.Run("logged out users skip without accessing the policy", func(t *testing.T) {
		u := syntheticUpdater(t, 1000)
		u.policy = "/not/a/real/policy"

		u.run = func([]string, string, map[string]string, string) (string, error) {
			return `[]`, nil
		}

		actual, err := u.eligible(1000)
		requireNoError(t, err)

		requireEqual(t, actual, false)
	})

	t.Run("missing policy is due", func(t *testing.T) {
		u := syntheticUpdater(t, 1000)

		actual, err := u.eligible(1000)
		requireNoError(t, err)

		requireEqual(t, actual, true)
	})

	t.Run("saved policy must be a root owned regular file", func(t *testing.T) {
		u := syntheticUpdater(t, 1000)
		requireNoError(t, os.Mkdir(u.policy, 0700))

		_, err := u.eligible(1000)
		requireError(t, err, "root-owned regular file")

		u.policy = filepath.Join(t.TempDir(), "policy")

		writeTestFile(t, u.policy, "previous policy")

		if os.Geteuid() != 0 {
			_, err := u.eligible(1000)
			requireError(t, err, "root-owned regular file")
		}
	})

	t.Run("freshness follows the local calendar day rather than elapsed hours", func(t *testing.T) {
		u := syntheticUpdater(t, 1000)

		writeTestFile(t, u.policy, "previous policy")

		info, err := os.Stat(u.policy)
		requireNoError(t, err)

		now := time.Date(2026, 10, 7, 0, 5, 0, 0, time.Local)

		for _, test := range []struct {
			mtime time.Time
			due   bool
		}{
			{now.Add(23 * time.Hour), false},
			{now.Add(-time.Minute), false},
			{now.Add(-10 * time.Minute), true},
			{now.AddDate(0, 0, -1), true},
		} {
			actual, err := policyDue(policyFileInfo{FileInfo: info, mtime: test.mtime}, now)
			requireNoError(t, err)

			requireEqual(t, actual, test.due)
		}
	})

	t.Run("condition errors fail instead of becoming service skips", func(t *testing.T) {
		for _, test := range []struct {
			name   string
			output string
			err    error
			status int
		}{
			{"due", `[{"uid":1000,"class":"user","session":"3"}]`, nil, 0},
			{"logged out", `[]`, nil, 1},
			{"discovery failure", "", errors.New("discovery failed"), 255},
		} {
			t.Run(test.name, func(t *testing.T) {
				u := syntheticUpdater(t, 1000)
				base := u.run

				u.run = func(args []string, stage string, env map[string]string, input string) (string, error) {
					if args[1] == "list-sessions" {
						return test.output, test.err
					}

					return base(args, stage, env, input)
				}

				command := cli{
					env:        configuredEnv(),
					updater:    u,
					lookupUser: syntheticUser,
					output:     io.Discard,
					errors:     io.Discard,
				}

				status := command.run([]string{"eligible"})

				requireEqual(t, status, test.status)
			})
		}
	})
}

func TestBrokerProtocol(t *testing.T) {
	t.Run("silent requests use Edge SharePoint and the unique matching account", func(t *testing.T) {
		u := newUpdater(io.Discard)
		var correlation string
		var methods []string

		u.run = func(args []string, stage string, env map[string]string, input string) (string, error) {
			requireEqual(t, args[:7], []string{"busctl", "--user", "--json=short", "call",
				"com.microsoft.identity.broker1", "/com/microsoft/identity/broker1", "com.microsoft.identity.Broker1"})
			requireEqual(t, args[8:10], []string{"sss", "0.0"})
			requireEqual(t, env["DBUS_SESSION_BUS_ADDRESS"], "unix:path=/run/user/1234/bus")
			requireEqual(t, env["XDG_RUNTIME_DIR"], "/run/user/1234")

			methods = append(methods, args[7])

			id, err := uuidString(args[10])
			requireNoError(t, err)

			requireEqual(t, id, args[10])
			requireEqual(t, id[14], byte('4'))

			if correlation != "" {
				requireEqual(t, args[10], correlation)
			}

			correlation = args[10]

			value, err := decodeJSON([]byte(args[11]), "synthetic request")
			requireNoError(t, err)

			request := value.(map[string]any)

			if args[7] == "getAccounts" {
				requireJSONEqual(t, request, map[string]any{"clientId": clientID, "redirectUri": redirectURI})

				return brokerEnvelope(t, map[string]any{"accounts": []any{
					map[string]any{"username": "other@example.com"}, testAccount(),
				}}), nil
			}

			requireEqual(t, args[7], "acquireTokenSilently")
			requireJSONEqual(t, request, map[string]any{"authParameters": map[string]any{
				"account": testAccount(), "username": "user@example.com",
				"authority":         "https://login.microsoftonline.com/12345678-1234-1234-1234-123456789abc",
				"authorizationType": 1, "clientId": clientID, "redirectUri": redirectURI,
				"requestedScopes": []string{"https://microsoft.sharepoint.com/.default"},
			}})

			return brokerEnvelope(t, map[string]any{"brokerTokenResponse": map[string]any{"accessToken": testToken}}), nil
		}

		token, err := u.accessToken(1234, "USER@example.com")
		requireNoError(t, err)

		requireEqual(t, token, testToken)
		requireEqual(t, methods, []string{"getAccounts", "acquireTokenSilently"})
	})

	t.Run("ambiguous accounts invalid realms and unusable tokens fail", func(t *testing.T) {
		for _, test := range []struct {
			name     string
			accounts any
			response any
			message  string
		}{
			{"missing accounts", nil, nil, "invalid account list"},
			{"invalid account", []any{"private"}, nil, "invalid account list"},
			{"no account", []any{}, nil, "exactly one"},
			{"ambiguous accounts", []any{testAccount(), testAccount()}, nil, "exactly one"},
			{"invalid realm", []any{map[string]any{"username": "user@example.com", "realm": "private"}}, nil, "invalid account tenant"},
			{"missing token", []any{testAccount()}, map[string]any{}, "no usable"},
			{"empty token", []any{testAccount()}, map[string]any{"accessToken": ""}, "no usable"},
			{"newline token", []any{testAccount()}, map[string]any{"accessToken": testToken + "\n"}, "no usable"},
			{"non-string token", []any{testAccount()}, map[string]any{"accessToken": 3}, "no usable"},
		} {
			t.Run(test.name, func(t *testing.T) {
				u := newUpdater(io.Discard)

				u.run = func(args []string, _ string, _ map[string]string, _ string) (string, error) {
					if args[7] == "getAccounts" {
						return brokerEnvelope(t, map[string]any{"accounts": test.accounts}), nil
					}

					return brokerEnvelope(t, map[string]any{"brokerTokenResponse": test.response}), nil
				}

				_, err := u.accessToken(1000, "user@example.com")
				requireError(t, err, test.message)

				if strings.Contains(err.Error(), testToken) || strings.Contains(err.Error(), "private") {
					t.Fatal("broker value leaked")
				}
			})
		}
	})

	t.Run("invalid envelopes and broker errors do not expose responses", func(t *testing.T) {
		for _, content := range []string{
			testToken, `[]`, `{}`, `{"type":"s","data":[]}`, `{"type":"s","data":[4]}`,
			`{"type":"x","data":["{}"]}`, `{"type":"s","data":["[]"]}`,
			brokerEnvelope(t, map[string]any{"error": map[string]any{"private": testToken}}),
		} {
			u := newUpdater(io.Discard)

			u.run = func([]string, string, map[string]string, string) (string, error) {
				return content, nil
			}

			_, err := u.broker("getAccounts", map[string]any{}, 1000, "synthetic")
			if err == nil || strings.Contains(err.Error(), testToken) {
				t.Fatalf("unsafe broker result: %v", err)
			}
		}
	})

	t.Run("UUID normalization accepts deployed broker tenant formats", func(t *testing.T) {
		want := "12345678-1234-1234-1234-123456789abc"

		for _, value := range []string{
			want, strings.ToUpper(want), "{" + want + "}", "urn:uuid:" + want, strings.ReplaceAll(want, "-", ""),
		} {
			actual, err := uuidString(value)
			requireNoError(t, err)

			requireEqual(t, actual, want)
		}
	})

	t.Run("Unicode case folded account aliases are not silently selected", func(t *testing.T) {
		for _, names := range [][2]string{
			{"stra\u00dfe", "STRASSE"},
			{"stra\u1e9ee", "STRASSE"},
			{"\u0130", "i\u0307"},
			{"\ufb03", "FFI"},
			{"\u1f80", "\u1f00\u03b9"},
			{"\u1f9f", "\u1f27\u03b9"},
			{"\u1fa8", "\u1f60\u03b9"},
			{"\u1ff7", "\u03c9\u0342\u03b9"},
			{"\ufb13", "\u0574\u0576"},
		} {
			u := newUpdater(io.Discard)

			u.run = func(args []string, _ string, _ map[string]string, _ string) (string, error) {
				requireEqual(t, args[7], "getAccounts")

				first, second := testAccount(), testAccount()
				first["username"], second["username"] = names[0]+"@example.com", names[1]+"@example.com"

				return brokerEnvelope(t, map[string]any{"accounts": []any{first, second}}), nil
			}

			_, err := u.accessToken(1000, names[0]+"@example.com")
			requireError(t, err, "exactly one configured account")
		}
	})
}

func TestProfileHTTP(t *testing.T) {
	t.Run("only the fixed file API receives authorization", func(t *testing.T) {
		u := syntheticUpdater(t, 1000)
		calls := 0

		u.client.Transport = roundTripFunc(func(request *http.Request) (*http.Response, error) {
			calls++

			if calls == 1 {
				requireEqual(t, request.URL.String(), "https://aka.ms/AzVPN")
				requireEqual(t, request.Header.Get("Authorization"), "")
				requireEqual(t, request.Header.Get("Accept-Encoding"), "")

				return httpResponse(301, "", "", testLink), nil
			}

			requireEqual(t, calls, 2)
			requireEqual(t, request.URL.Host, sharepoint)
			requireEqual(t, request.Header.Get("Authorization"), "Bearer "+testToken)
			requireEqual(t, request.Header.Get("Accept"), "application/xml")
			requireEqual(t, request.URL.RawQuery, "")

			if !strings.Contains(request.URL.Path, "GetFileByServerRelativePath") ||
				!strings.HasSuffix(request.URL.Path, "/$value") {
				t.Fatal("incorrect fixed API path")
			}

			return httpResponse(200, testXML, "application/xml", ""), nil
		})

		data, err := u.download(testToken)
		requireNoError(t, err)

		requireEqual(t, data, testPolicy(t))
		requireEqual(t, calls, 2)
	})

	t.Run("unexpected link targets are rejected", func(t *testing.T) {
		for _, location := range []string{
			strings.Replace(testLink, "https:", "http:", 1),
			strings.Replace(testLink, sharepoint, "example.com", 1),
			strings.Replace(testLink, sharepoint, sharepoint+".example.com", 1),
			strings.Replace(testLink, sharepoint, "user@"+sharepoint, 1),
			strings.Replace(testLink, sharepoint, sharepoint+":444", 1),
			strings.Replace(testLink, "Network_Connectivity", "AnotherSite", 1),
			strings.Replace(testLink, "Network_Connectivity", "network_connectivity", 1),
			strings.Replace(testLink, "/sites/", "/SITES/", 1),
			strings.Replace(testLink, "/Shared%20Documents/", "/%2e%2e/", 1),
			strings.Replace(testLink, "/Shared%20Documents/", "/%252e%252e/", 1),
			strings.Replace(testLink, "/Shared%20Documents/", "//", 1),
			strings.Replace(testLink, "/Shared%20Documents/", "/%00/", 1),
			strings.Replace(testLink, "/Shared%20Documents/", "/%5c/", 1),
			strings.Replace(testLink, "/Shared%20Documents/", "/%ff/", 1),
			strings.Replace(testLink, profile, "other.xml", 1),
			testLink + "#fragment", "https://[malformed",
		} {
			if _, err := apiPath(location); err == nil {
				t.Fatalf("accepted invalid synthetic location %q", location)
			}
		}
	})

	t.Run("OData quotes and spaces are encoded after one decode", func(t *testing.T) {
		target, err := apiPath(strings.Replace(testLink, "Shared%20Documents", "Team%27s%20Documents", 1))
		requireNoError(t, err)

		if !strings.Contains(target, "Team%27%27s%20Documents") || strings.Contains(target, "Team's") ||
			strings.Contains(target, "discard") {
			t.Fatal("incorrect OData escaping")
		}

		for _, port := range []string{"443", "0443"} {
			_, err = apiPath(strings.Replace(testLink, sharepoint, strings.ToUpper(sharepoint)+":"+port, 1))
			requireNoError(t, err)
		}
	})

	t.Run("redirects authorization failures HTML and malformed profiles fail", func(t *testing.T) {
		for _, test := range []struct {
			name    string
			status  int
			mime    string
			content string
		}{
			{"redirect", 302, "text/plain", ""},
			{"unauthorized", 401, "text/plain", testToken},
			{"forbidden", 403, "text/plain", testToken},
			{"HTML", 200, "text/HTML", "<html/>"},
			{"malformed XML", 200, "application/xml", testToken},
			{"missing routes", 200, "application/xml", "<profile/>"},
		} {
			t.Run(test.name, func(t *testing.T) {
				u := syntheticUpdater(t, 1000)
				calls := 0

				u.client.Transport = roundTripFunc(func(*http.Request) (*http.Response, error) {
					calls++

					if calls == 1 {
						return httpResponse(301, "", "", testLink), nil
					}

					if calls != 2 {
						t.Fatal("followed a forbidden redirect")
					}

					return httpResponse(test.status, test.content, test.mime, "https://example.com/private"), nil
				})

				_, err := u.download(testToken)
				if err == nil || strings.Contains(err.Error(), testToken) || strings.Contains(err.Error(), "example.com") {
					t.Fatalf("unsafe error: %v", err)
				}

				requireEqual(t, calls, 2)
			})
		}
	})

	t.Run("short link must return an allowed redirect", func(t *testing.T) {
		for _, status := range []int{200, 300, 304, 401, 500} {
			u := syntheticUpdater(t, 1000)

			u.client.Transport = roundTripFunc(func(*http.Request) (*http.Response, error) {
				return httpResponse(status, testToken, "", testLink), nil
			})

			_, err := u.download(testToken)
			requireError(t, err, "profile link: unexpected HTTP")
		}
	})

	t.Run("body size accepts exactly eight MiB and rejects overflow", func(t *testing.T) {
		for _, extra := range []int{0, 1} {
			u := syntheticUpdater(t, 1000)
			content := testXML + strings.Repeat(" ", maxBytes-len(testXML)+extra)
			calls := 0

			u.client.Transport = roundTripFunc(func(*http.Request) (*http.Response, error) {
				calls++

				if calls == 1 {
					return httpResponse(301, "", "", testLink), nil
				}

				return httpResponse(200, content, "application/xml", ""), nil
			})

			data, err := u.download(testToken)

			if extra == 0 {
				requireNoError(t, err)

				requireEqual(t, data, testPolicy(t))
			} else {
				requireError(t, err, "exceeds 8 MiB")
			}
		}
	})

	t.Run("production transport has no proxy redirects or automatic decompression", func(t *testing.T) {
		u := newUpdater(io.Discard)
		transport := u.client.Transport.(*http.Transport)
		if transport.Proxy != nil || !transport.DisableCompression {
			t.Fatal("unsafe transport defaults")
		}

		requireEqual(t, u.client.Timeout, 30*time.Second)
		requireEqual(t, u.client.CheckRedirect(nil, nil), http.ErrUseLastResponse)
	})

	t.Run("network and read failures never expose raw exceptions", func(t *testing.T) {
		for _, failAt := range []int{1, 2, 3} {
			u := syntheticUpdater(t, 1000)
			calls := 0

			u.client.Transport = roundTripFunc(func(*http.Request) (*http.Response, error) {
				calls++

				if calls == failAt {
					return nil, &url.Error{Op: "GET", URL: "https://private/" + testToken, Err: context.DeadlineExceeded}
				}

				if calls == 1 {
					return httpResponse(301, "", "", testLink), nil
				}

				response := httpResponse(200, "", "application/xml", "")
				response.Body = failingBody{}

				return response, nil
			})

			_, err := u.download(testToken)
			if err == nil || strings.Contains(err.Error(), testToken) || strings.Contains(err.Error(), "private") {
				t.Fatalf("unsafe network error: %v", err)
			}
		}
	})
}

func TestUpdateStorage(t *testing.T) {
	t.Run("fetch persists only route JSON and leaves the installed policy unchanged", func(t *testing.T) {
		u := syntheticUpdater(t, 1000)

		writeTestFile(t, u.policy, "previous policy")

		var output bytes.Buffer
		u.output = &output

		installSyntheticBroker(t, u)

		installSyntheticDownload(t, u)

		requireNoError(t, u.fetch(1000, "user@example.com"))

		actual, err := loadPolicy(u.candidate)
		requireNoError(t, err)

		requireEqual(t, actual, testPolicy(t))

		info, err := os.Stat(u.candidate)
		requireNoError(t, err)

		requireEqual(t, info.Mode().Perm(), os.FileMode(0600))
		requireEqual(t, readTestFile(t, u.policy), "previous policy")

		if strings.Contains(output.String(), testToken) || strings.Contains(readTestFile(t, u.candidate), testToken) {
			t.Fatal("token persisted or logged")
		}
	})

	t.Run("fetch failures preserve candidate and policy", func(t *testing.T) {
		for _, failure := range []string{"root", "wrong user", "logout", "broker", "network"} {
			t.Run(failure, func(t *testing.T) {
				u := syntheticUpdater(t, 1000)

				writeTestFile(t, u.policy, "previous policy")

				writeTestFile(t, u.candidate, "previous candidate")

				installSyntheticBroker(t, u)

				installSyntheticDownload(t, u)

				switch failure {
				case "root":
					u.euid = 0

				case "wrong user":
					u.euid = 1001

				case "logout":
					u.run = func([]string, string, map[string]string, string) (string, error) {
						return `[]`, nil
					}

				case "broker":
					base := u.run

					u.run = func(args []string, stage string, env map[string]string, input string) (string, error) {
						if args[0] == "busctl" {
							return "", errors.New("silent auth failed")
						}

						return base(args, stage, env, input)
					}

				case "network":
					u.client.Transport = roundTripFunc(func(*http.Request) (*http.Response, error) {
						return nil, errors.New("private response " + testToken)
					})
				}

				if err := u.fetch(1000, "user@example.com"); err == nil {
					t.Fatal("failed fetch succeeded")
				}

				requireEqual(t, readTestFile(t, u.policy), "previous policy")
				requireEqual(t, readTestFile(t, u.candidate), "previous candidate")
			})
		}
	})

	t.Run("install rejects logout wrong owner invalid candidates and unprivileged callers", func(t *testing.T) {
		for _, failure := range []string{"logout", "wrong owner", "invalid", "unprivileged"} {
			t.Run(failure, func(t *testing.T) {
				u := syntheticUpdater(t, os.Getuid())
				u.euid = 0

				writeTestFile(t, u.policy, "previous policy")

				requireNoError(t, atomicJSON(u.candidate, testPolicy(t), 0600, false))

				uid := os.Getuid()

				switch failure {
				case "logout":
					u.run = func([]string, string, map[string]string, string) (string, error) {
						return `[]`, nil
					}

				case "wrong owner":
					uid++

					u.run = signedInRunner(t, uid)

				case "invalid":
					writeTestFile(t, u.candidate, `{"accessToken":"private"}`)

				case "unprivileged":
					u.euid = 1000
				}

				if err := u.install(uid); err == nil {
					t.Fatal("invalid install succeeded")
				}

				requireEqual(t, readTestFile(t, u.policy), "previous policy")
			})
		}
	})

	t.Run("install writes validated root owned policy or preserves it when ownership fails", func(t *testing.T) {
		u := syntheticUpdater(t, os.Getuid())
		u.euid = 0

		writeTestFile(t, u.policy, "previous policy")

		requireNoError(t, atomicJSON(u.candidate, testPolicy(t), 0600, false))

		err := u.install(os.Getuid())

		if os.Geteuid() != 0 {
			if err == nil {
				t.Fatal("unprivileged chown unexpectedly succeeded")
			}

			requireEqual(t, readTestFile(t, u.policy), "previous policy")

			return
		}

		requireNoError(t, err)

		actual, err := loadPolicy(u.policy)
		requireNoError(t, err)

		requireEqual(t, actual, testPolicy(t))

		info, err := os.Stat(u.policy)
		requireNoError(t, err)

		requireEqual(t, info.Mode().Perm(), os.FileMode(0644))
	})
}

const (
	testToken = "synthetic-token-that-must-not-be-logged"
	testLink  = "https://microsoft.sharepoint.com/:u:/r/sites/Network_Connectivity/Shared%20Documents/AzVPN/MSFT-AzVPN-Manual.xml?discard=this"
)

func testAccount() map[string]any {
	return map[string]any{"username": "user@example.com", "realm": "12345678-1234-1234-1234-123456789abc"}
}

func configuredEnv() map[string]string {
	return map[string]string{"CORPNET_PROFILE_USER": "synthetic", "CORPNET_PROFILE_UPN": "user@example.com"}
}

func syntheticUser(string) (*user.User, error) {
	return &user.User{Uid: "1000"}, nil
}

func syntheticUpdater(t *testing.T, uid int) *updater {
	t.Helper()

	u := newUpdater(io.Discard)

	dir := t.TempDir()

	u.policy, u.candidate = filepath.Join(dir, "policy"), filepath.Join(dir, "candidate")
	u.euid = uid

	u.run = signedInRunner(t, uid)

	u.client.Transport = roundTripFunc(func(*http.Request) (*http.Response, error) {
		t.Fatal("unexpected HTTP operation in a synthetic test")

		return nil, errors.New("unexpected synthetic HTTP operation")
	})

	return u
}

func signedInRunner(t *testing.T, uid int) commandRunner {
	t.Helper()

	return func(args []string, stage string, env map[string]string, input string) (string, error) {
		if args[0] != "loginctl" {
			t.Fatal("unexpected external command in synthetic session test")
		}

		if args[1] == "list-sessions" {
			return fmt.Sprintf(`[{"uid":%d,"class":"user","session":"3"}]`, uid), nil
		}

		return "User=" + strconv.Itoa(uid) + "\nClass=user\nState=active\n", nil
	}
}

func brokerEnvelope(t *testing.T, response any) string {
	t.Helper()

	return string(encodeTestJSON(t, map[string]any{"type": "s", "data": []string{string(encodeTestJSON(t, response))}}))
}

func installSyntheticBroker(t *testing.T, u *updater) {
	t.Helper()

	base := u.run

	u.run = func(args []string, stage string, env map[string]string, input string) (string, error) {
		if args[0] != "busctl" {
			return base(args, stage, env, input)
		}

		if args[7] == "getAccounts" {
			return brokerEnvelope(t, map[string]any{"accounts": []any{testAccount()}}), nil
		}

		requireEqual(t, args[7], "acquireTokenSilently")

		return brokerEnvelope(t, map[string]any{"brokerTokenResponse": map[string]any{"accessToken": testToken}}), nil
	}
}

func installSyntheticDownload(t *testing.T, u *updater) {
	t.Helper()

	u.client.Transport = roundTripFunc(func(request *http.Request) (*http.Response, error) {
		if request.URL.Host == "aka.ms" {
			return httpResponse(301, "", "", testLink), nil
		}

		requireEqual(t, request.URL.Host, sharepoint)

		return httpResponse(200, testXML, "application/xml", ""), nil
	})
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(request *http.Request) (*http.Response, error) {
	return f(request)
}

func httpResponse(status int, content, mime, location string) *http.Response {
	header := make(http.Header)

	if mime != "" {
		header.Set("Content-Type", mime)
	}

	if location != "" {
		header.Set("Location", location)
	}

	return &http.Response{StatusCode: status, Header: header, Body: io.NopCloser(strings.NewReader(content))}
}

type failingBody struct{}

func (failingBody) Read([]byte) (int, error) {
	return 0, errors.New("private response " + testToken)
}

func (failingBody) Close() error {
	return nil
}

type policyFileInfo struct {
	os.FileInfo
	mtime time.Time
}

func (info policyFileInfo) ModTime() time.Time {
	return info.mtime
}

func (info policyFileInfo) Sys() any {
	return &syscall.Stat_t{Uid: 0}
}
