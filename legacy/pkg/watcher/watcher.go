package watcher

import (
	"fmt"
	"path/filepath"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
)

// FileWatcher watches files for changes and triggers callbacks
type FileWatcher struct {
	watcher   *fsnotify.Watcher
	mu        sync.Mutex
	callbacks map[string]func(string)
	debounce  time.Duration
	timers    map[string]*time.Timer
}

// NewFileWatcher creates a new file watcher
func NewFileWatcher(debounce time.Duration) (*FileWatcher, error) {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, fmt.Errorf("failed to create watcher: %w", err)
	}

	return &FileWatcher{
		watcher:   watcher,
		callbacks: make(map[string]func(string)),
		debounce:  debounce,
		timers:    make(map[string]*time.Timer),
	}, nil
}

// Watch starts watching the specified files
// callback will be called when any of the files change
func (fw *FileWatcher) Watch(files []string, callback func(string)) error {
	fw.mu.Lock()
	defer fw.mu.Unlock()

	// Add all files to watcher
	for _, file := range files {
		absPath, err := filepath.Abs(file)
		if err != nil {
			return fmt.Errorf("failed to resolve path %s: %w", file, err)
		}

		if err := fw.watcher.Add(absPath); err != nil {
			return fmt.Errorf("failed to watch %s: %w", absPath, err)
		}

		fw.callbacks[absPath] = callback
	}

	return nil
}

// Start begins watching for file changes
func (fw *FileWatcher) Start() {
	go func() {
		for {
			select {
			case event, ok := <-fw.watcher.Events:
				if !ok {
					return
				}

				// Only trigger on write or create events
				if event.Op&fsnotify.Write == fsnotify.Write || event.Op&fsnotify.Create == fsnotify.Create {
					fw.handleFileChange(event.Name)
				}

			case err, ok := <-fw.watcher.Errors:
				if !ok {
					return
				}
				fmt.Printf("Watcher error: %v\n", err)
			}
		}
	}()
}

// handleFileChange handles a file change event with debouncing
func (fw *FileWatcher) handleFileChange(filePath string) {
	fw.mu.Lock()
	defer fw.mu.Unlock()

	// Get the callback for this file
	callback, exists := fw.callbacks[filePath]
	if !exists {
		return
	}

	// Cancel existing timer if any
	if timer, exists := fw.timers[filePath]; exists {
		timer.Stop()
	}

	// Create a new debounced timer
	fw.timers[filePath] = time.AfterFunc(fw.debounce, func() {
		callback(filePath)
	})
}

// Close stops the watcher
func (fw *FileWatcher) Close() error {
	return fw.watcher.Close()
}

// RemoveAll removes all watched files
func (fw *FileWatcher) RemoveAll() error {
	fw.mu.Lock()
	defer fw.mu.Unlock()

	for file := range fw.callbacks {
		if err := fw.watcher.Remove(file); err != nil {
			return err
		}
	}

	fw.callbacks = make(map[string]func(string))
	fw.timers = make(map[string]*time.Timer)
	return nil
}
