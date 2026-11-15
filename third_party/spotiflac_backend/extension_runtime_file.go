package gobackend

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/dop251/goja"
)

var (
	allowedDownloadDirs   []string
	allowedDownloadDirsMu sync.RWMutex
)

func SetAllowedDownloadDirs(dirs []string) {
	allowedDownloadDirsMu.Lock()
	defer allowedDownloadDirsMu.Unlock()
	allowedDownloadDirs = dirs
	GoLog("[Extension] Allowed download directories set: %v\n", dirs)
}

func AddAllowedDownloadDir(dir string) {
	allowedDownloadDirsMu.Lock()
	defer allowedDownloadDirsMu.Unlock()
	absDir, err := filepath.Abs(dir)
	if err == nil {
		allowedDownloadDirs = append(allowedDownloadDirs, absDir)
	}
}

func isPathInAllowedDirs(absPath string) bool {
	allowedDownloadDirsMu.RLock()
	defer allowedDownloadDirsMu.RUnlock()

	for _, allowedDir := range allowedDownloadDirs {
		if isPathWithinBase(allowedDir, absPath) {
			return true
		}
	}
	return false
}

func isPathWithinBase(baseDir, targetPath string) bool {
	baseAbs, err := filepath.Abs(baseDir)
	if err != nil {
		return false
	}
	targetAbs, err := filepath.Abs(targetPath)
	if err != nil {
		return false
	}

	rel, err := filepath.Rel(baseAbs, targetAbs)
	if err != nil {
		return false
	}
	rel = filepath.Clean(rel)
	if rel == "." {
		return true
	}

	prefix := ".." + string(filepath.Separator)
	if rel == ".." || strings.HasPrefix(rel, prefix) {
		return false
	}
	return true
}

func (r *extensionRuntime) validatePath(path string) (string, error) {
	if !r.manifest.Permissions.File {
		return "", fmt.Errorf("file access denied: extension does not have 'file' permission")
	}

	cleanPath := filepath.Clean(path)

	if filepath.IsAbs(cleanPath) {
		absPath, err := filepath.Abs(cleanPath)
		if err != nil {
			return "", fmt.Errorf("invalid path: %w", err)
		}

		if isPathInAllowedDirs(absPath) {
			return absPath, nil
		}

		return "", fmt.Errorf("file access denied: absolute paths are not allowed. Use relative paths within extension sandbox")
	}

	fullPath := filepath.Join(r.dataDir, cleanPath)

	absPath, err := filepath.Abs(fullPath)
	if err != nil {
		return "", fmt.Errorf("invalid path: %w", err)
	}

	absDataDir, _ := filepath.Abs(r.dataDir)
	if !isPathWithinBase(absDataDir, absPath) {
		return "", fmt.Errorf("file access denied: path '%s' is outside sandbox", path)
	}

	return absPath, nil
}

func (r *extensionRuntime) fileDownload(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "URL and output path are required",
		})
	}

	urlStr := call.Arguments[0].String()
	outputPath := call.Arguments[1].String()

	if err := r.validateDomain(urlStr); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	fullPath, err := r.validatePath(outputPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	var onProgress goja.Callable
	var headers map[string]string
	var chunkedDownload bool
	trackItemBytes := true
	var chunkSize int64
	if len(call.Arguments) > 2 && !goja.IsUndefined(call.Arguments[2]) && !goja.IsNull(call.Arguments[2]) {
		optionsObj := call.Arguments[2].Export()
		if opts, ok := optionsObj.(map[string]interface{}); ok {
			if h, ok := opts["headers"].(map[string]interface{}); ok {
				headers = make(map[string]string)
				for k, v := range h {
					headers[k] = fmt.Sprintf("%v", v)
				}
			}
			if progressVal, ok := opts["onProgress"]; ok {
				if callable, ok := goja.AssertFunction(r.vm.ToValue(progressVal)); ok {
					onProgress = callable
				}
			}
			if trackBytes, ok := opts["trackItemBytes"]; ok {
				if v, ok := trackBytes.(bool); ok {
					trackItemBytes = v
				}
			} else if trackBytes, ok := opts["track_item_bytes"]; ok {
				if v, ok := trackBytes.(bool); ok {
					trackItemBytes = v
				}
			}
			if chunked, ok := opts["chunked"]; ok {
				switch v := chunked.(type) {
				case bool:
					chunkedDownload = v
				case int64:
					if v > 0 {
						chunkedDownload = true
						chunkSize = v
					}
				case float64:
					if v > 0 {
						chunkedDownload = true
						chunkSize = int64(v)
					}
				}
			}
		}
	}

	// Default chunk size: 1MB (YouTube CDN max without poToken)
	if chunkedDownload && chunkSize <= 0 {
		chunkSize = 1024 * 1024
	}

	dir := filepath.Dir(fullPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to create directory: %v", err),
		})
	}

	client := r.downloadClient
	if client == nil {
		client = r.httpClient
	}

	ua := appUserAgent()
	if h, ok := headers["User-Agent"]; ok && h != "" {
		ua = h
	}

	if chunkedDownload {
		return r.fileDownloadChunked(client, urlStr, fullPath, headers, ua, chunkSize, onProgress, trackItemBytes)
	}

	req, err := http.NewRequest("GET", urlStr, nil)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}
	req = r.bindDownloadCancelContext(req)

	for k, v := range headers {
		req.Header.Set(k, v)
	}
	if req.Header.Get("User-Agent") == "" {
		req.Header.Set("User-Agent", appUserAgent())
	}

	resp, err := client.Do(req)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("HTTP error: %d", resp.StatusCode),
		})
	}

	out, err := os.Create(fullPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to create file: %v", err),
		})
	}
	defer out.Close()

	activeItemID := r.getActiveDownloadItemID()
	if activeItemID != "" {
		SetItemDownloading(activeItemID)
	}

	contentLength := resp.ContentLength
	shouldTrackItemBytes := activeItemID != "" && trackItemBytes
	if shouldTrackItemBytes && contentLength > 0 {
		SetItemBytesTotal(activeItemID, contentLength)
	}

	var progressWriter interface{ Write([]byte) (int, error) } = out
	if shouldTrackItemBytes {
		progressWriter = NewItemProgressWriter(out, activeItemID)
	}

	var written int64
	buf := make([]byte, 32*1024)
	for {
		nr, er := resp.Body.Read(buf)
		if nr > 0 {
			nw, ew := progressWriter.Write(buf[0:nr])
			if nw < 0 || nr < nw {
				nw = 0
				if ew == nil {
					ew = fmt.Errorf("invalid write result")
				}
			}
			written += int64(nw)
			if ew != nil {
				if ew == ErrDownloadCancelled {
					return r.vm.ToValue(map[string]interface{}{
						"success": false,
						"error":   "download cancelled",
					})
				}
				return r.vm.ToValue(map[string]interface{}{
					"success": false,
					"error":   fmt.Sprintf("failed to write file: %v", ew),
				})
			}
			if nr != nw {
				return r.vm.ToValue(map[string]interface{}{
					"success": false,
					"error":   "short write",
				})
			}

			if onProgress != nil && contentLength > 0 {
				_, _ = onProgress(goja.Undefined(), r.vm.ToValue(written), r.vm.ToValue(contentLength))
			}
		}
		if er != nil {
			if er != io.EOF {
				return r.vm.ToValue(map[string]interface{}{
					"success": false,
					"error":   fmt.Sprintf("failed to read response: %v", er),
				})
			}
			break
		}
	}

	if shouldTrackItemBytes {
		if contentLength > 0 {
			SetItemProgress(activeItemID, float64(written)/float64(contentLength), written, contentLength)
		} else if written > 0 {
			SetItemBytesReceived(activeItemID, written)
		}
	}

	GoLog("[Extension:%s] Downloaded %d bytes to %s\n", r.extensionID, written, fullPath)

	return r.vm.ToValue(map[string]interface{}{
		"success": true,
		"path":    fullPath,
		"size":    written,
	})
}

// fileDownloadChunked downloads a URL using sequential Range requests.
// This is needed for servers (like YouTube's googlevideo CDN) that reject
// non-ranged or large-range requests with 403 and require small chunk downloads.
func (r *extensionRuntime) fileDownloadChunked(client *http.Client, urlStr, fullPath string, headers map[string]string, ua string, chunkSize int64, onProgress goja.Callable, trackItemBytes bool) goja.Value {
	// First, get the total content length with a small probe request
	probeReq, err := http.NewRequest("GET", urlStr, nil)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("chunked: probe request error: %v", err),
		})
	}
	probeReq = r.bindDownloadCancelContext(probeReq)
	probeReq.Header.Set("User-Agent", ua)
	for k, v := range headers {
		if k != "Range" { // Don't copy any existing Range header
			probeReq.Header.Set(k, v)
		}
	}
	probeReq.Header.Set("Range", "bytes=0-1")

	probeResp, err := client.Do(probeReq)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("chunked: probe error: %v", err),
		})
	}
	io.Copy(io.Discard, probeResp.Body)
	probeResp.Body.Close()

	if probeResp.StatusCode != 206 && probeResp.StatusCode != 200 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("chunked: probe HTTP %d", probeResp.StatusCode),
		})
	}

	// Parse Content-Range to get total size: "bytes 0-1/TOTAL"
	var totalSize int64
	contentRange := probeResp.Header.Get("Content-Range")
	if contentRange != "" {
		if idx := strings.LastIndex(contentRange, "/"); idx >= 0 {
			sizeStr := contentRange[idx+1:]
			if sizeStr != "*" {
				fmt.Sscanf(sizeStr, "%d", &totalSize)
			}
		}
	}

	if totalSize <= 0 {
		// Fallback: try Content-Length from a HEAD-like approach
		// If we can't determine size, download with unknown size
		GoLog("[Extension:%s] Chunked download: unknown total size, will download until server says done\n", r.extensionID)
	} else {
		GoLog("[Extension:%s] Chunked download: total size %d bytes, chunk size %d\n", r.extensionID, totalSize, chunkSize)
	}

	out, err := os.Create(fullPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to create file: %v", err),
		})
	}
	defer out.Close()

	activeItemID := r.getActiveDownloadItemID()
	if activeItemID != "" {
		SetItemDownloading(activeItemID)
	}

	shouldTrackItemBytes := activeItemID != "" && trackItemBytes
	if shouldTrackItemBytes && totalSize > 0 {
		SetItemBytesTotal(activeItemID, totalSize)
	}

	var progressWriter interface{ Write([]byte) (int, error) } = out
	if shouldTrackItemBytes {
		progressWriter = NewItemProgressWriter(out, activeItemID)
	}

	var totalWritten int64
	buf := make([]byte, 32*1024)
	maxRetries := 3

	for offset := int64(0); totalSize <= 0 || offset < totalSize; {
		end := offset + chunkSize - 1
		if totalSize > 0 && end >= totalSize {
			end = totalSize - 1
		}

		var chunkResp *http.Response
		var chunkErr error

		for retry := 0; retry < maxRetries; retry++ {
			chunkReq, err := http.NewRequest("GET", urlStr, nil)
			if err != nil {
				return r.vm.ToValue(map[string]interface{}{
					"success": false,
					"error":   fmt.Sprintf("chunked: request error at offset %d: %v", offset, err),
				})
			}
			chunkReq = r.bindDownloadCancelContext(chunkReq)
			chunkReq.Header.Set("User-Agent", ua)
			for k, v := range headers {
				if k != "Range" {
					chunkReq.Header.Set(k, v)
				}
			}
			chunkReq.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", offset, end))

			chunkResp, chunkErr = client.Do(chunkReq)
			if chunkErr != nil {
				if retry < maxRetries-1 {
					time.Sleep(time.Duration(retry+1) * time.Second)
					continue
				}
				return r.vm.ToValue(map[string]interface{}{
					"success": false,
					"error":   fmt.Sprintf("chunked: error at offset %d after %d retries: %v", offset, maxRetries, chunkErr),
				})
			}

			if chunkResp.StatusCode == 206 || chunkResp.StatusCode == 200 {
				break // Success
			}

			io.Copy(io.Discard, chunkResp.Body)
			chunkResp.Body.Close()

			if chunkResp.StatusCode == 403 || chunkResp.StatusCode == 429 {
				if retry < maxRetries-1 {
					time.Sleep(time.Duration(retry+1) * 2 * time.Second)
					continue
				}
			}

			return r.vm.ToValue(map[string]interface{}{
				"success": false,
				"error":   fmt.Sprintf("chunked: HTTP %d at offset %d", chunkResp.StatusCode, offset),
			})
		}

		chunkWritten := int64(0)
		for {
			nr, er := chunkResp.Body.Read(buf)
			if nr > 0 {
				nw, ew := progressWriter.Write(buf[0:nr])
				if nw < 0 || nr < nw {
					nw = 0
					if ew == nil {
						ew = fmt.Errorf("invalid write result")
					}
				}
				chunkWritten += int64(nw)
				totalWritten += int64(nw)
				if ew != nil {
					chunkResp.Body.Close()
					if ew == ErrDownloadCancelled {
						return r.vm.ToValue(map[string]interface{}{
							"success": false,
							"error":   "download cancelled",
						})
					}
					return r.vm.ToValue(map[string]interface{}{
						"success": false,
						"error":   fmt.Sprintf("failed to write file: %v", ew),
					})
				}
				if nr != nw {
					chunkResp.Body.Close()
					return r.vm.ToValue(map[string]interface{}{
						"success": false,
						"error":   "short write",
					})
				}

				if onProgress != nil && totalSize > 0 {
					_, _ = onProgress(goja.Undefined(), r.vm.ToValue(totalWritten), r.vm.ToValue(totalSize))
				}
			}
			if er != nil {
				if er != io.EOF {
					chunkResp.Body.Close()
					return r.vm.ToValue(map[string]interface{}{
						"success": false,
						"error":   fmt.Sprintf("failed to read chunk at offset %d: %v", offset, er),
					})
				}
				break
			}
		}
		chunkResp.Body.Close()

		offset += chunkWritten

		// If server returned 200 (full content) instead of 206, we're done
		if chunkResp.StatusCode == 200 {
			break
		}

		// If we got less data than expected and we know total size, check if done
		if totalSize > 0 && offset >= totalSize {
			break
		}

		// Unknown size: if we got less than chunk size, assume done
		if totalSize <= 0 && chunkWritten < chunkSize {
			break
		}
	}

	if shouldTrackItemBytes {
		if totalSize > 0 {
			SetItemProgress(activeItemID, float64(totalWritten)/float64(totalSize), totalWritten, totalSize)
		} else if totalWritten > 0 {
			SetItemBytesReceived(activeItemID, totalWritten)
		}
	}

	GoLog("[Extension:%s] Chunked download complete: %d bytes to %s\n", r.extensionID, totalWritten, fullPath)

	return r.vm.ToValue(map[string]interface{}{
		"success": true,
		"path":    fullPath,
		"size":    totalWritten,
	})
}

func (r *extensionRuntime) fileExists(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(false)
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.vm.ToValue(false)
	}

	_, err = os.Stat(fullPath)
	return r.vm.ToValue(err == nil)
}

func (r *extensionRuntime) fileDelete(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "path is required",
		})
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	if err := os.Remove(fullPath); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	return r.vm.ToValue(map[string]interface{}{
		"success": true,
	})
}

func (r *extensionRuntime) fileRead(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "path is required",
		})
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	data, err := os.ReadFile(fullPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	return r.vm.ToValue(map[string]interface{}{
		"success": true,
		"data":    string(data),
	})
}

func (r *extensionRuntime) fileReadBytes(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "path is required",
		})
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	options := parseRuntimeOptionsArgument(call, 1)
	offset := runtimeOptionInt64(options, "offset", 0)
	length := runtimeOptionInt64(options, "length", -1)
	encoding := runtimeOptionString(options, "encoding", "base64")
	if offset < 0 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "offset must be >= 0",
		})
	}
	file, err := os.Open(fullPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	size := info.Size()
	if offset > size {
		offset = size
	}
	if _, err := file.Seek(offset, io.SeekStart); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to seek file: %v", err),
		})
	}

	var data []byte
	switch {
	case length == 0:
		data = []byte{}
	case length > 0:
		buf := make([]byte, int(length))
		n, readErr := file.Read(buf)
		if readErr != nil && readErr != io.EOF {
			return r.vm.ToValue(map[string]interface{}{
				"success": false,
				"error":   fmt.Sprintf("failed to read file: %v", readErr),
			})
		}
		data = buf[:n]
	default:
		data, err = io.ReadAll(file)
		if err != nil {
			return r.vm.ToValue(map[string]interface{}{
				"success": false,
				"error":   fmt.Sprintf("failed to read file: %v", err),
			})
		}
	}

	if strings.EqualFold(strings.TrimSpace(encoding), "bytes") ||
		strings.EqualFold(strings.TrimSpace(encoding), "raw") {
		// Return raw bytes as an ArrayBuffer to avoid base64 encode/decode of
		// large payloads under the goja interpreter.
		return r.vm.ToValue(map[string]interface{}{
			"success":    true,
			"data":       r.vm.NewArrayBuffer(data),
			"bytes_read": len(data),
			"offset":     offset,
			"size":       size,
			"eof":        offset+int64(len(data)) >= size,
		})
	}

	encoded, err := encodeRuntimeBytes(data, encoding)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	return r.vm.ToValue(map[string]interface{}{
		"success":    true,
		"data":       encoded,
		"bytes_read": len(data),
		"offset":     offset,
		"size":       size,
		"eof":        offset+int64(len(data)) >= size,
	})
}
func (r *extensionRuntime) fileWrite(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "path and data are required",
		})
	}

	path := call.Arguments[0].String()
	data := call.Arguments[1].String()

	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	dir := filepath.Dir(fullPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to create directory: %v", err),
		})
	}

	if err := os.WriteFile(fullPath, []byte(data), 0644); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	return r.vm.ToValue(map[string]interface{}{
		"success": true,
		"path":    fullPath,
	})
}

func (r *extensionRuntime) fileWriteBytes(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "path and data are required",
		})
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	options := parseRuntimeOptionsArgument(call, 2)
	appendMode := runtimeOptionBool(options, "append", false)
	truncate := runtimeOptionBool(options, "truncate", false)
	hasOffset := runtimeOptionHasKey(options, "offset")
	offset := runtimeOptionInt64(options, "offset", 0)
	encoding := runtimeOptionString(options, "encoding", "base64")

	if appendMode && hasOffset {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "append and offset cannot be used together",
		})
	}
	if offset < 0 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "offset must be >= 0",
		})
	}

	data, err := decodeRuntimeBytesValue(call.Arguments[1].Export(), encoding)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	dir := filepath.Dir(fullPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to create directory: %v", err),
		})
	}

	flags := os.O_CREATE | os.O_WRONLY
	if appendMode {
		flags |= os.O_APPEND
	}
	if truncate {
		flags |= os.O_TRUNC
	}

	file, err := os.OpenFile(fullPath, flags, 0644)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}
	defer file.Close()

	if hasOffset && !appendMode {
		if _, err := file.Seek(offset, io.SeekStart); err != nil {
			return r.vm.ToValue(map[string]interface{}{
				"success": false,
				"error":   fmt.Sprintf("failed to seek file: %v", err),
			})
		}
	}

	written, err := file.Write(data)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	info, statErr := file.Stat()
	size := int64(0)
	if statErr == nil {
		size = info.Size()
	}

	return r.vm.ToValue(map[string]interface{}{
		"success":       true,
		"path":          fullPath,
		"bytes_written": written,
		"size":          size,
	})
}

func (r *extensionRuntime) fileCopy(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "source and destination paths are required",
		})
	}

	srcPath := call.Arguments[0].String()
	dstPath := call.Arguments[1].String()

	fullSrc, err := r.validatePath(srcPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	fullDst, err := r.validatePath(dstPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	srcFile, err := os.Open(fullSrc)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to read source: %v", err),
		})
	}
	defer srcFile.Close()

	dir := filepath.Dir(fullDst)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to create directory: %v", err),
		})
	}

	dstFile, err := os.OpenFile(fullDst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to open destination: %v", err),
		})
	}

	if _, err := io.Copy(dstFile, srcFile); err != nil {
		_ = dstFile.Close()
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to copy file: %v", err),
		})
	}

	if err := dstFile.Close(); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to finalize destination: %v", err),
		})
	}

	return r.vm.ToValue(map[string]interface{}{
		"success": true,
		"path":    fullDst,
	})
}

func (r *extensionRuntime) fileMove(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "source and destination paths are required",
		})
	}

	srcPath := call.Arguments[0].String()
	dstPath := call.Arguments[1].String()

	fullSrc, err := r.validatePath(srcPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	fullDst, err := r.validatePath(dstPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	dir := filepath.Dir(fullDst)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to create directory: %v", err),
		})
	}

	if err := os.Rename(fullSrc, fullDst); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to move file: %v", err),
		})
	}

	return r.vm.ToValue(map[string]interface{}{
		"success": true,
		"path":    fullDst,
	})
}

func (r *extensionRuntime) fileGetSize(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "path is required",
		})
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	info, err := os.Stat(fullPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	return r.vm.ToValue(map[string]interface{}{
		"success": true,
		"size":    info.Size(),
	})
}
