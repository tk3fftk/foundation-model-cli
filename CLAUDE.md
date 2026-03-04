# CLAUDE.md

## Build & Test

```bash
swift build              # debug build
swift build -c release   # release build
```

## Swift + Network framework: SIGTRAP の罠

### `dispatchMain()` を async 関数から呼んではいけない

`dispatchMain()` は内部で `pthread_exit(NULL)` を呼び、呼び出し元スレッドを終了させる。`async` 関数は Swift concurrency のスレッドプール上で実行されるため、そのスレッドが殺されるとランタイムのアサーション違反で SIGTRAP になる。

```swift
// NG: async 関数内で dispatchMain()
func start() async throws {
    listener.start(queue: .global())
    dispatchMain() // SIGTRAP
}

// OK: AsyncStream + シグナルハンドラで待機
func start() async throws {
    listener.start(queue: .global())
    let signals = AsyncStream<Void> { continuation in
        let src = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        src.setEventHandler { continuation.finish() }
        src.resume()
    }
    for await _ in signals {}
    withExtendedLifetime(listener) {}
}
```

### `NWConnection.cancel()` を複数箇所から呼んではいけない

既に cancelled 状態の NWConnection に対して `cancel()` を呼ぶと SIGTRAP になる。cancel は1箇所に集約すること。

```swift
// NG: defer と send completion の両方で cancel
func handle(connection: NWConnection) async {
    defer { connection.cancel() }      // cancel #1
    // ...
    send(connection: connection, ...)   // send 内で cancel #2 → SIGTRAP
}

// OK: send の completion handler でのみ cancel
func handle(connection: NWConnection) async {
    // defer なし
    send(connection: connection, ...)
}
func send(connection: NWConnection, ...) {
    connection.send(content: data, completion: .contentProcessed { _ in
        connection.cancel()  // ここだけで cancel
    })
}
```

### `NWConnection.receive` の `isComplete` は TCP FIN を意味する

`isComplete == true` は「相手が接続を閉じた」ことを示す。HTTP クライアント (curl 等) はリクエスト送信後もレスポンスを待つため接続を開いたままにする。`isComplete` を guard 条件にするとリクエストが処理されず "Empty reply from server" になる。

```swift
// NG: isComplete を要求
connection.receive(...) { data, _, isComplete, error in
    guard error == nil, isComplete else { return }  // curl のリクエストが拒否される
}

// OK: isComplete を無視
connection.receive(...) { data, _, _, error in
    guard error == nil else { return }
}
```
