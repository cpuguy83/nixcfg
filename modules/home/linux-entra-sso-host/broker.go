package main

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"log/slog"
	"sync"

	"github.com/godbus/dbus/v5"
)

const (
	// Session bus broker (broker <= 2.0.1)
	userBrokerBusName   = "com.microsoft.identity.broker1"
	userBrokerObjPath   = "/com/microsoft/identity/broker1"
	userBrokerInterface = "com.microsoft.identity.Broker1"

	// System bus device broker (broker > 2.0.1)
	deviceBrokerBusName   = "com.microsoft.identity.devicebroker1"
	deviceBrokerObjPath   = "/com/microsoft/identity/devicebroker1"
	deviceBrokerInterface = "com.microsoft.identity.DeviceBroker1"

	// Edge browser client ID - used as the default client for SSO operations
	edgeBrowserClientID = "d7b530a4-7680-4c23-a8bf-c52c121d2e87"

	// Default authority
	defaultAuthority = "https://login.microsoftonline.com/common"

	// Protocol version
	protocolVersion = "0.0"
)

// Authorization types
const (
	AuthTypeToken     = 1 // For acquireTokenSilently
	AuthTypeSSOCookie = 8 // For acquirePrtSsoCookie (OAUTH2)
)

type Broker struct {
	conn          *dbus.Conn
	obj           dbus.BusObject
	sessionID     string
	mu            sync.RWMutex
	stateCh       chan bool
	interfaceName string
	busName       string
	useSystemBus  bool
}

func NewBroker() (*Broker, error) {
	// Always use session bus - broker is D-Bus activated on demand
	sessionConn, err := dbus.SessionBus()
	if err != nil {
		return nil, fmt.Errorf("failed to connect to session bus: %w", err)
	}

	slog.Debug("Using session bus broker", "name", userBrokerBusName)
	b := &Broker{
		conn:          sessionConn,
		obj:           sessionConn.Object(userBrokerBusName, userBrokerObjPath),
		sessionID:     generateSessionID(),
		stateCh:       make(chan bool, 1),
		interfaceName: userBrokerInterface,
		busName:       userBrokerBusName,
		useSystemBus:  false,
	}

	go b.watchNameOwner()
	return b, nil
}

func (b *Broker) Close() error {
	close(b.stateCh)
	return b.conn.Close()
}

func (b *Broker) WatchState() <-chan bool {
	return b.stateCh
}

func (b *Broker) watchNameOwner() {
	// Subscribe to NameOwnerChanged for the broker service
	rule := fmt.Sprintf("type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='%s'", b.busName)
	b.conn.BusObject().Call("org.freedesktop.DBus.AddMatch", 0, rule)

	ch := make(chan *dbus.Signal, 10)
	b.conn.Signal(ch)

	for sig := range ch {
		if sig.Name == "org.freedesktop.DBus.NameOwnerChanged" && len(sig.Body) >= 3 {
			name, _ := sig.Body[0].(string)
			newOwner, _ := sig.Body[2].(string)
			if name == b.busName {
				online := newOwner != ""
				select {
				case b.stateCh <- online:
				default:
				}
			}
		}
	}
}

func generateSessionID() string {
	// Generate a UUID v4 for the session
	b := make([]byte, 16)
	rand.Read(b)
	// Set version (4) and variant (RFC 4122)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x",
		b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// callMethod makes a D-Bus method call with the standard signature (sss) -> s
func (b *Broker) callMethod(method string, params any) (map[string]any, error) {
	paramsJSON, err := json.Marshal(params)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal params: %w", err)
	}

	slog.Debug("D-Bus call", "method", method, "params", string(paramsJSON))

	var result string
	err = b.obj.Call(b.interfaceName+"."+method, 0,
		protocolVersion,
		b.sessionID,
		string(paramsJSON),
	).Store(&result)

	if err != nil {
		return nil, fmt.Errorf("D-Bus call %s failed: %w", method, err)
	}

	slog.Debug("D-Bus response", "result", result)

	var response map[string]any
	if err := json.Unmarshal([]byte(result), &response); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	// Check for broker errors - can be a string or an object
	if errObj, ok := response["error"].(map[string]any); ok {
		errJSON, _ := json.Marshal(errObj)
		return response, fmt.Errorf("broker error: %s", errJSON)
	}
	if errMsg, ok := response["error"].(string); ok && errMsg != "" {
		return nil, fmt.Errorf("broker error: %s", errMsg)
	}

	return response, nil
}

func (b *Broker) GetAccounts() ([]map[string]any, error) {
	context := map[string]any{
		"clientId":    edgeBrowserClientID,
		"redirectUri": b.sessionID,
	}

	resp, err := b.callMethod("getAccounts", context)
	if err != nil {
		return nil, err
	}

	// Extract accounts from response
	accounts, ok := resp["accounts"].([]any)
	if !ok {
		return []map[string]any{}, nil
	}

	result := make([]map[string]any, 0, len(accounts))
	for _, acc := range accounts {
		if accMap, ok := acc.(map[string]any); ok {
			result = append(result, accMap)
		}
	}

	return result, nil
}

func (b *Broker) GetLinuxBrokerVersion() (map[string]any, error) {
	return b.callMethod("getLinuxBrokerVersion", map[string]any{})
}

func (b *Broker) AcquirePrtSsoCookie(account map[string]any, ssoURL string) (map[string]any, error) {
	request := map[string]any{
		"account":        account,
		"authParameters": b.getAuthParameters(account, nil, ssoURL),
		"ssoUrl":         ssoURL,
	}

	resp, err := b.callMethod("acquirePrtSsoCookie", request)
	if err != nil {
		return nil, err
	}

	// Handle the different response formats
	// Newer brokers return {"cookieItems": [{"cookieName": ..., "cookieContent": ...}]}
	if cookieItems, ok := resp["cookieItems"].([]any); ok && len(cookieItems) > 0 {
		if item, ok := cookieItems[0].(map[string]any); ok {
			return item, nil
		}
	}

	// Older brokers might return the cookie directly
	if _, ok := resp["cookieName"]; ok {
		return resp, nil
	}

	return resp, nil
}

func (b *Broker) AcquireTokenSilently(account map[string]any, scopes []string) (map[string]any, error) {
	request := map[string]any{
		"account":        account,
		"authParameters": b.getAuthParameters(account, scopes, ""),
	}

	return b.callMethod("acquireTokenSilently", request)
}

func (b *Broker) getAuthParameters(account map[string]any, scopes []string, ssoURL string) map[string]any {
	// Determine auth type: 8 for SSO cookies, 1 for token acquisition
	authType := AuthTypeToken
	if ssoURL != "" {
		authType = AuthTypeSSOCookie
	}

	// Use tenant-specific authority if we have realm info
	authority := defaultAuthority
	if account != nil {
		if realm, ok := account["realm"].(string); ok && realm != "" {
			authority = "https://login.microsoftonline.com/" + realm
		}
	}

	if len(scopes) == 0 {
		scopes = []string{"https://graph.microsoft.com/.default"}
	}

	params := map[string]any{
		"account":           account,
		"authority":         authority,
		"authorizationType": authType,
		"clientId":          edgeBrowserClientID,
		"redirectUri":       b.sessionID,
		"requestedScopes":   scopes,
	}

	// Add ssoUrl to auth parameters for SSO cookie requests
	if ssoURL != "" {
		params["ssoUrl"] = ssoURL
	}

	// Add username if available
	if account != nil {
		if username, ok := account["username"].(string); ok {
			params["username"] = username
		}
	}

	return params
}
