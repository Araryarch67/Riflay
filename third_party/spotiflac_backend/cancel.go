package gobackend

import (
	"context"
	"errors"
	"sync"
)

// ErrDownloadCancelled is returned when a download is cancelled by the user.
var ErrDownloadCancelled = errors.New("download cancelled")

// ErrExtensionRequestCancelled is returned when a UI-driven extension request
// is superseded by a newer home/search request.
var ErrExtensionRequestCancelled = errors.New("extension request cancelled")

type cancelEntry struct {
	ctx      context.Context
	cancel   context.CancelFunc
	canceled bool
	refs     int
}

var (
	cancelMu  sync.Mutex
	cancelMap = make(map[string]*cancelEntry)

	extensionRequestCancelMu  sync.Mutex
	extensionRequestCancelMap = make(map[string]*cancelEntry)
)

func initDownloadCancel(itemID string) context.Context {
	if itemID == "" {
		return context.Background()
	}

	cancelMu.Lock()
	defer cancelMu.Unlock()

	if entry, ok := cancelMap[itemID]; ok {
		if entry.ctx == nil {
			ctx, cancel := context.WithCancel(context.Background())
			entry.ctx = ctx
			entry.cancel = cancel
			if entry.canceled && entry.cancel != nil {
				entry.cancel()
			}
		}
		entry.refs++
		return entry.ctx
	}

	ctx, cancel := context.WithCancel(context.Background())
	cancelMap[itemID] = &cancelEntry{
		ctx:      ctx,
		cancel:   cancel,
		canceled: false,
		refs:     1,
	}
	return ctx
}

func cancelDownload(itemID string) {
	if itemID == "" {
		return
	}

	cancelMu.Lock()
	entry, ok := cancelMap[itemID]
	if ok {
		entry.canceled = true
		if entry.cancel != nil {
			entry.cancel()
		}
	} else {
		cancelMap[itemID] = &cancelEntry{canceled: true}
	}
	cancelMu.Unlock()

	RemoveItemProgress(itemID)
}

func isDownloadCancelled(itemID string) bool {
	if itemID == "" {
		return false
	}

	cancelMu.Lock()
	entry, ok := cancelMap[itemID]
	canceled := ok && entry.canceled
	cancelMu.Unlock()
	return canceled
}

func clearDownloadCancel(itemID string) {
	if itemID == "" {
		return
	}

	cancelMu.Lock()
	if entry, ok := cancelMap[itemID]; ok {
		entry.refs--
		if entry.refs <= 0 {
			delete(cancelMap, itemID)
		}
	}
	cancelMu.Unlock()
}

func initExtensionRequestCancel(requestID string) context.Context {
	if requestID == "" {
		return context.Background()
	}

	extensionRequestCancelMu.Lock()
	defer extensionRequestCancelMu.Unlock()

	if entry, ok := extensionRequestCancelMap[requestID]; ok {
		if entry.ctx == nil {
			ctx, cancel := context.WithCancel(context.Background())
			entry.ctx = ctx
			entry.cancel = cancel
			if entry.canceled && entry.cancel != nil {
				entry.cancel()
			}
		}
		entry.refs++
		return entry.ctx
	}

	ctx, cancel := context.WithCancel(context.Background())
	extensionRequestCancelMap[requestID] = &cancelEntry{
		ctx:      ctx,
		cancel:   cancel,
		canceled: false,
		refs:     1,
	}
	return ctx
}

func cancelExtensionRequest(requestID string) {
	if requestID == "" {
		return
	}

	extensionRequestCancelMu.Lock()
	if entry, ok := extensionRequestCancelMap[requestID]; ok {
		entry.canceled = true
		if entry.cancel != nil {
			entry.cancel()
		}
	} else {
		extensionRequestCancelMap[requestID] = &cancelEntry{canceled: true}
	}
	extensionRequestCancelMu.Unlock()
}

func isExtensionRequestCancelled(requestID string) bool {
	if requestID == "" {
		return false
	}

	extensionRequestCancelMu.Lock()
	entry, ok := extensionRequestCancelMap[requestID]
	canceled := ok && entry.canceled
	extensionRequestCancelMu.Unlock()
	return canceled
}

func clearExtensionRequestCancel(requestID string) {
	if requestID == "" {
		return
	}

	extensionRequestCancelMu.Lock()
	if entry, ok := extensionRequestCancelMap[requestID]; ok {
		entry.refs--
		if entry.refs <= 0 {
			delete(extensionRequestCancelMap, requestID)
		}
	}
	extensionRequestCancelMu.Unlock()
}
