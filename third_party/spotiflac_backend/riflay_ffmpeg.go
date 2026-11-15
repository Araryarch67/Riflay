package gobackend

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"sync"
	"time"
	"unicode"
)

var riflayFFmpeg struct {
	sync.RWMutex
	enabled    bool
	executable string
}

func RiflaySetFFmpegPath(path string) {
	riflayFFmpeg.Lock()
	defer riflayFFmpeg.Unlock()
	riflayFFmpeg.enabled = true
	riflayFFmpeg.executable = path
}

// Tokenize arguments without a shell, accepting both Windows paths and Go %q paths.
func riflaySplitArgs(command string) ([]string, error) {
	var args []string
	for i := 0; i < len(command); {
		for i < len(command) && unicode.IsSpace(rune(command[i])) {
			i++
		}
		if i == len(command) {
			break
		}
		var token strings.Builder
		for i < len(command) && !unicode.IsSpace(rune(command[i])) {
			if command[i] == '"' || command[i] == '\'' {
				quote := command[i]
				i++
				closed := false
				for i < len(command) {
					if command[i] == quote {
						i++
						closed = true
						break
					}
					if command[i] == '\\' && i+1 < len(command) && (command[i+1] == quote || command[i+1] == '\\') {
						i++
					}
					token.WriteByte(command[i])
					i++
				}
				if !closed {
					return nil, fmt.Errorf("unclosed FFmpeg argument")
				}
			} else {
				token.WriteByte(command[i])
				i++
			}
		}
		args = append(args, token.String())
	}
	return args, nil
}

func (r *extensionRuntime) riflayRunFFmpeg(command string) map[string]interface{} {
	fail := func(err error) map[string]interface{} {
		return map[string]interface{}{"success": false, "error": err.Error()}
	}
	riflayFFmpeg.RLock()
	executable := riflayFFmpeg.executable
	riflayFFmpeg.RUnlock()
	if executable == "" {
		return fail(fmt.Errorf("FFmpeg is not configured"))
	}
	args, err := riflaySplitArgs(command)
	if err != nil {
		return fail(err)
	}
	if len(args) < 3 {
		return fail(fmt.Errorf("invalid FFmpeg arguments"))
	}
	flags := map[string]bool{"-i": true, "-c:a": true, "-c": true, "-acodec": true, "-codec:a": true, "-b:a": true, "-ar": true, "-ac": true, "-map": true, "-f": true, "-metadata": true, "-movflags": true, "-map_metadata": true, "-id3v2_version": true, "-write_id3v1": true, "-compression_level": true, "-sample_fmt": true, "-threads": true, "-c:v": true, "-loglevel": true}
	switches := map[string]bool{"-y": true, "-n": true, "-vn": true, "-sn": true, "-dn": true, "-an": true, "-nostdin": true, "-hide_banner": true}
	for i := 0; i < len(args)-1; i++ {
		flag := args[i]
		if switches[flag] {
			continue
		}
		if !flags[flag] || i+1 >= len(args)-1 {
			return fail(fmt.Errorf("unsupported FFmpeg option"))
		}
		i++
		if flag == "-i" {
			args[i], err = r.validatePath(args[i])
			if err != nil {
				return fail(err)
			}
		}
		if flag == "-f" && !strings.Contains("|flac|mp3|adts|ogg|opus|ipod|mp4|wav|", "|"+args[i]+"|") {
			return fail(fmt.Errorf("unsupported FFmpeg format"))
		}
	}
	args[len(args)-1], err = r.validatePath(args[len(args)-1])
	if err != nil {
		return fail(err)
	}
	args = append([]string{"-nostdin", "-hide_banner", "-loglevel", "error", "-protocol_whitelist", "file,pipe,crypto"}, args...)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	output, err := exec.CommandContext(ctx, executable, args...).CombinedOutput()
	if err != nil {
		return fail(fmt.Errorf("FFmpeg conversion failed"))
	}
	return map[string]interface{}{"success": true, "output": string(output)}
}
