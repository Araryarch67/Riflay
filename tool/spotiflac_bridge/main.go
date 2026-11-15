package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"riflay/spotiflac_bridge/bridge"
	"sync"
)

func main() {
	output := os.Stdout
	os.Stdout = os.Stderr
	if len(os.Args) != 2 {
		return
	}
	root, err := filepath.Abs(os.Args[1])
	if err != nil {
		return
	}
	if err = bridge.Initialize(root); err != nil {
		return
	}
	defer bridge.Shutdown()
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 65536), 4<<20)
	var writes sync.Mutex
	var tasks sync.WaitGroup
	for scanner.Scan() {
		payload := scanner.Text()
		tasks.Add(1)
		go func() {
			defer tasks.Done()
			response := bridge.Invoke(payload, root)
			writes.Lock()
			_, _ = fmt.Fprintln(output, response)
			writes.Unlock()
		}()
	}
	tasks.Wait()
}
