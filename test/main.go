package main

import (
	"encoding/json"
	"flag"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"
)

var serviceName string
var httpPort int

func main() {
	os.WriteFile("/run/app.pid", []byte(strconv.Itoa(os.Getpid())), os.ModePerm)
	flag.IntVar(&httpPort, "httpPort", 8080, "http listen port")
	flag.StringVar(&serviceName, "serviceName", "test", "override the service name")
	flag.Parse()

	r := http.NewServeMux()
	r.HandleFunc("/api/v1/ping", ping)
	r.HandleFunc("/test/api/v1/ping", ping)
	log.Fatal(http.ListenAndServe(":"+strconv.FormatInt(int64(httpPort), 10), r))
}

func ping(w http.ResponseWriter, r *http.Request) {
	message := "healthy"
	hostname,err := os.Hostname()
	if err != nil {
		message = "hostname call failed"
	}
	pr := pingResponse{
		ServiceName: serviceName,
		ServiceType: "OPTIONAL",
		ServiceState: "oneline",
		Message: message,
		LastUpdated: time.Now(),
		DefaultCharset: "UTF-8",
	}
	pr.ServiceInstance.InstanceID = "TODO"
	pr.ServiceInstance.Host =hostname
	pr.ServiceInstance.Port =httpPort

	json.NewEncoder(w).Encode(pr)
}

type pingResponse struct {
	ServiceName     string `json:"serviceName"`
	ServiceType     string `json:"serviceType"`
	ServiceState    string `json:"serviceState"`
	Message         string `json:"message"`
	ServiceInstance struct {
		InstanceID string `json:"instanceId"`
		Host       string `json:"host"`
		Port       int    `json:"port"`
	} `json:"serviceInstance"`
	LastUpdated      time.Time `json:"lastUpdated"`
	UpstreamServices []struct {
		ServiceName      string        `json:"serviceName"`
		ServiceType      string        `json:"serviceType"`
		ServiceState     string        `json:"serviceState"`
		Message          string        `json:"message"`
		LastUpdated      time.Time     `json:"lastUpdated"`
		BaseURL          string        `json:"baseUrl,omitempty"`
		DurationPretty   string        `json:"durationPretty"`
		Duration         int           `json:"duration"`
		UpstreamServices []interface{} `json:"upstreamServices"`
		DefaultCharset   string        `json:"defaultCharset"`
	} `json:"upstreamServices"`
	DefaultCharset string `json:"defaultCharset"`
}
