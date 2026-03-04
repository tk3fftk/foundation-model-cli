# Implementation Plan - OpenAI API互換エンドポイント

## 目的
- `fm` に OpenAI API 互換のエンドポイント起動オプションを追加する。
- 既存の単発CLI応答モードは維持する。

## 最小変更方針
1. `main.swift` に `--openai-compatible-api-endpoint`（short: `-o`）を追加。
   - 値あり: `host:port` で起動
   - 値なし: `localhost` の空きポートを `4000` から探索して起動
2. このオプション指定時のみ簡易HTTPサーバーを起動。
3. 互換対象は最小限として以下を提供:
   - `GET /v1/models`
   - `POST /v1/chat/completions`（`stream: true` は未対応として明示エラー）
4. 既存生成ロジックを関数化して通常CLIとAPIモードで共用。
5. `README.md` に利用例を追加。

## 検証計画
- 既存の `swift build` / `swift test` を実行して現状把握。
- 変更後に再度 `swift build` / `swift test` を試行（環境依存失敗は記録）。
- macOS環境での手動確認想定:
  - `fm --openai-compatible-api-endpoint 127.0.0.1:4000`
  - `curl` で `/v1/models` と `/v1/chat/completions` を確認。
