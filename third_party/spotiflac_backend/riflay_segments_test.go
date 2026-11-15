package gobackend

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dop251/goja"
)

type riflaySegmentTransport func(*http.Request) (*http.Response, error)

func (f riflaySegmentTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func TestRiflaySegmentsResumeAndConcatenate(t *testing.T) {
	root := t.TempDir()
	vm := goja.New()
	requests := map[string]int{}
	allowMedia := false
	client := &http.Client{Transport: riflaySegmentTransport(func(req *http.Request) (*http.Response, error) {
		requests[req.URL.Path]++
		if req.URL.Path == "/media" && !allowMedia {
			return nil, fmt.Errorf("connection closed")
		}
		body := strings.TrimPrefix(req.URL.Path, "/")
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), ContentLength: int64(len(body)), Header: http.Header{}}, nil
	})}
	runtime := &extensionRuntime{vm: vm, dataDir: root, httpClient: client, downloadClient: client,
		manifest: &ExtensionManifest{Permissions: ExtensionPermissions{File: true, Network: []string{"cdn.example.org"}}}}
	vm.Set("downloadSegments", runtime.riflayDownloadSegments)
	script := `downloadSegments(["https://cdn.example.org/init","https://cdn.example.org/media"], "audio.m4a", {persistentCheckpoint:true})`
	value, err := vm.RunString(script)
	if err != nil {
		t.Fatal(err)
	}
	if value.ToObject(vm).Get("success").ToBoolean() {
		t.Fatal("interrupted transfer was reported as success")
	}
	if _, err := os.Stat(filepath.Join(root, "audio.m4a")); !os.IsNotExist(err) {
		t.Fatal("partial output was published")
	}
	allowMedia = true
	value, err = vm.RunString(script)
	if err != nil || !value.ToObject(vm).Get("success").ToBoolean() {
		t.Fatalf("resume failed: %v %v", value, err)
	}
	body, err := os.ReadFile(filepath.Join(root, "audio.m4a"))
	if err != nil || string(body) != "initmedia" {
		t.Fatalf("wrong fragment order: %q %v", body, err)
	}
	if requests["/init"] != 1 {
		t.Fatal("completed fragment was downloaded again")
	}
	before := requests["/media"]
	value, err = vm.RunString(`downloadSegments(["https://unapproved.example.org/media"], "bad.m4a")`)
	if err != nil || value.ToObject(vm).Get("success").ToBoolean() || requests["/media"] != before {
		t.Fatal("network permissions were bypassed")
	}
}
