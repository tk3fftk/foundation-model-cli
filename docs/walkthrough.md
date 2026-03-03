# Walkthrough - OpenAI API互換エンドポイント追加

## 追加した内容
- `fm --openai-compatible-api-endpoint`（short: `-o`）を追加。
- 値を省略すると `localhost` の空きポートを `4000` から自動選択。
- 指定時は通常の単発生成の代わりにHTTPサーバーを起動。
- OpenAI互換の最小APIとして以下を実装:
  - `GET /v1/models`
  - `POST /v1/chat/completions`

## リクエスト仕様（最小）
- `messages` の `role: "user"` 最後の `content` を入力プロンプトとして使用。
- `role: "system"` はCLIの `--system-prompt` と結合して利用。
- `temperature` はリクエスト値があれば優先。
- `stream: true` は未対応（400エラーを返却）。

## レスポンス仕様（最小）
- `chat.completion` 形式で `choices[0].message.role = "assistant"` を返却。
- `usage` は互換維持のため固定値（0）を返却。

## 実行例
```bash
fm --openai-compatible-api-endpoint 127.0.0.1:4000
```

```bash
curl -s http://127.0.0.1:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"foundation-model-cli","messages":[{"role":"user","content":"こんにちは"}]}'
```
