package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"

	"github.com/joho/godotenv"
	"github.com/openai/openai-go"
	"github.com/openai/openai-go/option"
	"github.com/openai/openai-go/responses"
)

// WeatherRequest defines the structure for incoming weather requests
type WeatherRequest struct {
	Location string `json:"location"`
}

// WeatherResponse defines the structure for weather responses
type WeatherResponse struct {
	Temperature int    `json:"temperature"`
	Units       string `json:"units"`
}

const (
	chatModel = openai.ChatModelGPT4o
	o3Model   = openai.ChatModelO3Mini
)

func main() {
	// Load environment variables
	err := godotenv.Load()
	if err != nil {
		fmt.Printf("Warning: Error loading .env file: %v\n", err)
		os.Exit(1)
	}
	apiKey := os.Getenv("OPENAI_API_KEY")
	if apiKey == "" {
		fmt.Fprintf(os.Stderr, "OPENAI_API_KEY is not set\n")
		os.Exit(1)
	}

	http.HandleFunc("/session", func(w http.ResponseWriter, r *http.Request) {
		sessionKey, err := createSessionKey(apiKey)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			fmt.Fprintf(w, "Error creating session key. %v\n", err)
			return
		}

		response := struct {
			Success bool   `json:"success"`
			Key     string `json:"key"`
		}{
			Success: true,
			Key:     sessionKey,
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
	})

	http.HandleFunc("/chat", func(w http.ResponseWriter, r *http.Request) {
		client := createOpenaiChatClient()
		bodyBytes, err := io.ReadAll(r.Body)
		defer r.Body.Close()
		if err != nil {
			fmt.Fprintf(w, "Error reading request body: %v\n", err)
			return
		}
		userQuery := string(bodyBytes)

		response, err := client.Responses.New(
			context.Background(),
			responses.ResponseNewParams{
				Model: chatModel,
				Input: responses.ResponseNewParamsInputUnion{
					OfString: openai.String(userQuery),
				},
			},
		)
		if err != nil {
			fmt.Fprintf(w, "Error creating chat completion: %v\n", err)
		}

		fmt.Fprintf(w, "%s", response.OutputText())
	})

	// Serve index.html on the root route
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// Only serve the root path
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		// Serve the index.html file
		indexPath := filepath.Join(".", "index.html")
		http.ServeFile(w, r, indexPath)
	})

	// Register the getWeather tool endpoint
	http.HandleFunc("/tools/getWeather", getWeatherHandler)

	// Register the reasoning endpoint
	http.HandleFunc("/reasoning", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		client := createOpenaiChatClient()
		bodyBytes, err := io.ReadAll(r.Body)
		defer r.Body.Close()
		if err != nil {
			http.Error(w, fmt.Sprintf("Error reading request body: %v", err), http.StatusBadRequest)
			return
		}
		userQuery := string(bodyBytes)

		response, err := client.Responses.New(
			context.Background(),
			responses.ResponseNewParams{
				Model: o3Model,
				Input: responses.ResponseNewParamsInputUnion{
					OfString: openai.String(userQuery),
				},
			},
		)
		if err != nil {
			http.Error(w, fmt.Sprintf("Error creating chat completion: %v", err), http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "text/plain")
		fmt.Fprintf(w, "%s", response.OutputText())
	})

	fmt.Println("http://localhost:8080")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		fmt.Printf("Error starting server: %v\n", err)
	}
}

// getWeatherHandler processes weather requests and returns a fixed response
func getWeatherHandler(w http.ResponseWriter, r *http.Request) {
	// Only accept POST requests
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Read the request body
	var weatherReq WeatherRequest
	err := json.NewDecoder(r.Body).Decode(&weatherReq)
	if err != nil {
		http.Error(w, fmt.Sprintf("Error parsing request body: %v", err), http.StatusBadRequest)
		return
	}
	defer r.Body.Close()

	// Log the received location
	fmt.Printf("Weather request received for location: %s\n", weatherReq.Location)

	// Create a fixed weather response (18°C for any location)
	weatherResp := WeatherResponse{
		Temperature: 18,
		Units:       "C",
	}

	// Set content type header and return the JSON response
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(weatherResp); err != nil {
		http.Error(w, fmt.Sprintf("Error encoding response: %v", err), http.StatusInternalServerError)
		return
	}
}

func createOpenaiChatClient() openai.Client {
	err := godotenv.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading .env file: %v\n", err)
		os.Exit(1)
	}

	apiKey := os.Getenv("OPENAI_API_KEY")
	if apiKey == "" {
		fmt.Fprintf(os.Stderr, "OPENAI_API_KEY is not set\n")
		os.Exit(1)
	}

	client := openai.NewClient(
		option.WithAPIKey(apiKey),
	)
	return client
}

func createSessionKey(apiKey string) (string, error) {
	reqBody := struct {
		Model string `json:"model"`
		Voice string `json:"voice"`
	}{
		Model: "gpt-4o-realtime-preview-2024-12-17",
		Voice: "echo",
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return "", err
	}

	req, err := http.NewRequest("POST", "https://api.openai.com/v1/realtime/sessions", bytes.NewReader(jsonBody))
	if err != nil {
		return "", err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)

	token, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer token.Body.Close()

	if token.StatusCode != http.StatusOK {
		return "", fmt.Errorf("openai request failed: %d", token.StatusCode)
	}

	bodyBytes, err := io.ReadAll(token.Body)
	if err != nil {
		return "", err
	}

	var tokenResponse struct {
		ClientSecret struct {
			Value string `json:"value"`
		} `json:"client_secret"`
	}

	if err := json.Unmarshal(bodyBytes, &tokenResponse); err != nil {
		return "", fmt.Errorf("failed to decode token response: %v", err)
	}

	if tokenResponse.ClientSecret.Value == "" {
		return "", fmt.Errorf("received empty client secret from OpenAI API")
	}

	return tokenResponse.ClientSecret.Value, nil
}
