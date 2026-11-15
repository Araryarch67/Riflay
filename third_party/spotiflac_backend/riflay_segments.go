package gobackend

import (
	"crypto/sha256"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/dop251/goja"
)

// file.downloadSegments downloads initialization/media fragments in order and
// atomically publishes their concatenation. Completed fragments survive retries.
// All network and file access uses the existing extension sandbox.
func (r *extensionRuntime) riflayDownloadSegments(call goja.FunctionCall) goja.Value {
	fail := func(err error) goja.Value {
		kind := "download_error"
		if isDownloadCancelled(r.getActiveDownloadItemID()) {
			kind = "cancelled"
		}
		return r.vm.ToValue(map[string]interface{}{"success": false, "error": err.Error(), "error_type": kind})
	}
	if len(call.Arguments) < 2 {
		return fail(fmt.Errorf("URLs and output path are required"))
	}
	var urls []string
	if err := r.vm.ExportTo(call.Arguments[0], &urls); err != nil || len(urls) == 0 || len(urls) > 4096 {
		return fail(fmt.Errorf("invalid segment list"))
	}
	for _, url := range urls {
		if err := r.validateDomain(url); err != nil {
			return fail(err)
		}
	}
	path, err := r.validatePath(call.Arguments[1].String())
	if err != nil {
		return fail(err)
	}
	headers := map[string]string{}
	persistent := false
	var progress goja.Callable
	if len(call.Arguments) > 2 && !goja.IsUndefined(call.Arguments[2]) && !goja.IsNull(call.Arguments[2]) {
		opts := call.Arguments[2].ToObject(r.vm)
		if value := opts.Get("headers"); value != nil && !goja.IsUndefined(value) {
			_ = r.vm.ExportTo(value, &headers)
		}
		persistent = opts.Get("persistentCheckpoint") != nil && opts.Get("persistentCheckpoint").ToBoolean()
		progress, _ = goja.AssertFunction(opts.Get("onProgress"))
	}
	if err = os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return fail(err)
	}
	hash := sha256.Sum256([]byte(strings.Join(urls, "\n")))
	cache := fmt.Sprintf("%s.segments-%x", path, hash[:8])
	if err = os.MkdirAll(cache, 0700); err != nil {
		return fail(err)
	}
	if !persistent {
		defer os.RemoveAll(cache)
	}
	item := r.getActiveDownloadItemID()
	client := r.downloadClient
	if client == nil {
		client = r.httpClient
	}
	var written int64
	for i, url := range urls {
		if isDownloadCancelled(item) {
			return fail(ErrDownloadCancelled)
		}
		segment := filepath.Join(cache, fmt.Sprintf("%06d", i))
		stat, statErr := os.Stat(segment)
		if statErr != nil || stat.Size() == 0 {
			var last error
			for attempt := 0; attempt < 3; attempt++ {
				if isDownloadCancelled(item) {
					return fail(ErrDownloadCancelled)
				}
				last = r.riflayFetchSegment(client, url, segment, headers)
				if last == nil {
					break
				}
				if attempt < 2 {
					time.Sleep(time.Duration(attempt+1) * 250 * time.Millisecond)
				}
			}
			if last != nil {
				return fail(last)
			}
			stat, err = os.Stat(segment)
			if err != nil {
				return fail(err)
			}
		}
		written += stat.Size()
		if item != "" {
			SetItemBytesReceived(item, written)
		}
		if progress != nil {
			if _, err := progress(goja.Undefined(), r.vm.ToValue(written), r.vm.ToValue(0), r.vm.ToValue(i+1), r.vm.ToValue(len(urls))); err != nil {
				return fail(err)
			}
		}
	}
	out, err := os.CreateTemp(filepath.Dir(path), ".riflay-merge-*")
	if err != nil {
		return fail(err)
	}
	temporary := out.Name()
	defer os.Remove(temporary)
	for i := range urls {
		if isDownloadCancelled(item) {
			out.Close()
			return fail(ErrDownloadCancelled)
		}
		in, err := os.Open(filepath.Join(cache, fmt.Sprintf("%06d", i)))
		if err != nil {
			out.Close()
			return fail(err)
		}
		_, err = io.Copy(out, in)
		in.Close()
		if err != nil {
			out.Close()
			return fail(err)
		}
	}
	if err = out.Sync(); err != nil {
		out.Close()
		return fail(err)
	}
	if err = out.Close(); err != nil {
		return fail(err)
	}
	if err = os.Rename(temporary, path); err != nil {
		return fail(err)
	}
	_ = os.RemoveAll(cache)
	return r.vm.ToValue(map[string]interface{}{"success": true, "path": path, "size": written})
}

func (r *extensionRuntime) riflayFetchSegment(client *http.Client, url, path string, headers map[string]string) error {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return err
	}
	req = r.bindDownloadCancelContext(req)
	for key, value := range headers {
		req.Header.Set(key, value)
	}
	if req.Header.Get("User-Agent") == "" {
		req.Header.Set("User-Agent", appUserAgent())
	}
	response, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("segment request failed")
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		return fmt.Errorf("segment HTTP %d", response.StatusCode)
	}
	out, err := os.Create(path + ".part")
	if err != nil {
		return err
	}
	defer os.Remove(path + ".part")
	const limit = int64(256 << 20)
	size, copyErr := io.Copy(out, io.LimitReader(response.Body, limit+1))
	closeErr := out.Close()
	if copyErr != nil {
		return fmt.Errorf("segment transfer interrupted")
	}
	if closeErr != nil {
		return closeErr
	}
	if size == 0 || size > limit || (response.ContentLength >= 0 && size != response.ContentLength) {
		return fmt.Errorf("incomplete or oversized segment")
	}
	return os.Rename(path+".part", path)
}
