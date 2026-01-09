package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
)

const version = "1.0.0"

func main() {
	interactive := flag.Bool("interactive", false, "Run in interactive mode")
	accountIdx := flag.Int("account", 0, "Account index to use (interactive mode)")
	ssoURL := flag.String("sso-url", "", "SSO URL (interactive mode)")
	showVersion := flag.Bool("version", false, "Show version")
	debug := flag.Bool("debug", false, "Enable debug logging")
	flag.Parse()

	logOpts := &slog.HandlerOptions{}
	if *debug {
		logOpts.Level = slog.LevelDebug
	}

	logger := slog.New(slog.NewTextHandler(os.Stderr, logOpts))
	slog.SetDefault(logger)

	if *showVersion {
		fmt.Printf("linux-entra-sso-host %s\n", version)
		os.Exit(0)
	}

	// Set up parent death signal (Linux-specific)
	setPDeathSig()

	broker, err := NewBroker()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Failed to connect to broker:", err)
		os.Exit(1)
	}

	defer broker.Close()

	if *interactive {
		runInteractive(broker, *accountIdx, *ssoURL)
	} else {
		runNativeMessaging(broker)
	}
}

func setPDeathSig() {
	// When parent process dies, we receive SIGINT
	// This is important for Chrome/Chromium which may not properly clean up
	const prSetPdeathsig = 1
	syscall.Syscall(syscall.SYS_PRCTL, prSetPdeathsig, uintptr(syscall.SIGINT), 0)
}

func runInteractive(broker *Broker, accountIdx int, ssoURL string) {
	// First get broker version
	ver, err := broker.GetLinuxBrokerVersion()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Warning: Failed to get broker version", "error", err)
	} else {
		verJSON, _ := json.MarshalIndent(ver, "", "  ")
		fmt.Println("Broker version:", string(verJSON))
	}

	accounts, err := broker.GetAccounts()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Failed to get accounts:", err)
		os.Exit(1)
	}

	slog.Debug("Found accounts", "num", len(accounts))
	for i, acc := range accounts {
		accJSON, _ := json.MarshalIndent(acc, "", "  ")
		slog.Info("Account", "index", i, "details", string(accJSON))
	}

	if len(accounts) == 0 {
		fmt.Fprintln(os.Stderr, "No accounts found")
		os.Exit(2)
	}

	if accountIdx >= len(accounts) {
		fmt.Fprintln(os.Stderr, "Account index out of range", "index", accountIdx, "numAccounts", len(accounts))
		os.Exit(1)
	}

	account := accounts[accountIdx]

	if ssoURL == "" {
		ssoURL = "https://login.microsoftonline.com/"
	}

	cookie, err := broker.AcquirePrtSsoCookie(account, ssoURL)
	if err != nil {
		slog.Error("Failed to acquire PRT SSO cookie", "error", err)
		os.Exit(1)
	}

	output, _ := json.MarshalIndent(cookie, "", "  ")
	fmt.Println(string(output))

	// Also test acquireTokenSilently
	token, err := broker.AcquireTokenSilently(account, nil)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Failed to acquire token silently:", err)
		os.Exit(1)
	}

	tokenJSON, _ := json.MarshalIndent(token, "", "  ")
	fmt.Printf("\nToken response:\n%s\n", tokenJSON)
}

func runNativeMessaging(broker *Broker) {
	// Set up signal handler
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		os.Exit(0)
	}()

	messenger := NewMessenger(os.Stdin, os.Stdout)

	// Send initial broker state (we're connected if we got here)
	messenger.Send(map[string]any{
		"command": "brokerStateChanged",
		"message": "online",
	})

	// Subscribe to broker state changes
	go func() {
		stateCh := broker.WatchState()
		for online := range stateCh {
			state := "offline"
			if online {
				state = "online"
			}
			msg := map[string]any{
				"command": "brokerStateChanged",
				"message": state,
			}
			messenger.Send(msg)
		}
	}()

	// Main message loop
	for {
		req, err := messenger.Receive()
		if err != nil {
			// EOF or read error - exit gracefully
			if !errors.Is(err, io.EOF) {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
			return
		}

		resp := handleRequest(broker, req)
		if err := messenger.Send(resp); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
			return
		}
	}
}

func handleRequest(broker *Broker, req map[string]any) map[string]any {
	command, _ := req["command"].(string)

	response := map[string]any{
		"command": command,
	}

	switch command {
	case "getAccounts":
		accounts, err := broker.GetAccounts()
		if err != nil {
			response["error"] = err.Error()
		} else {
			response["message"] = map[string]any{
				"accounts": accounts,
			}
		}

	case "getVersion":
		ver, err := broker.GetLinuxBrokerVersion()
		if err != nil {
			response["error"] = err.Error()
		} else {
			brokerVersion, _ := ver["linuxBrokerVersion"].(string)
			response["message"] = map[string]any{
				"native":             version,
				"linuxBrokerVersion": brokerVersion,
			}
		}

	case "acquirePrtSsoCookie":
		account, _ := req["account"].(map[string]any)
		ssoURL, _ := req["ssoUrl"].(string)
		if ssoURL == "" {
			ssoURL = "https://login.microsoftonline.com/"
		}

		cookie, err := broker.AcquirePrtSsoCookie(account, ssoURL)
		if err != nil {
			response["error"] = err.Error()
		} else {
			response["message"] = cookie
		}

	case "acquireTokenSilently":
		account, _ := req["account"].(map[string]any)
		scopes, _ := req["scopes"].([]any)
		scopeStrs := make([]string, len(scopes))
		for i, s := range scopes {
			scopeStrs[i], _ = s.(string)
		}

		token, err := broker.AcquireTokenSilently(account, scopeStrs)
		if err != nil {
			response["error"] = err.Error()
		} else {
			// Broker already returns {brokerTokenResponse: {...}, telemetry: {...}}
			response["message"] = token
		}

	default:
		response["error"] = fmt.Sprintf("unknown command: %s", command)
	}

	return response
}
