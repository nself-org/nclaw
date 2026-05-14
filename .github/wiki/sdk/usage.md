# SDK Usage Examples

Quick examples for each supported language.

## TypeScript / Node.js

```typescript
import { NclawClient } from '@nself/nclaw-sdk';

// Initialize client
const client = new NclawClient({
  serverUrl: 'http://localhost:8080',
  jwt: process.env.NCLAW_JWT
});

// Fetch messages in a topic
const messages = await client.messages.list({
  topicId: 'topic-uuid-here'
});

// Create a new message
const newMsg = await client.messages.create({
  topicId: 'topic-uuid-here',
  content: 'Hello, ɳClaw',
  role: 'user'
});
```

## Dart / Flutter

```dart
import 'package:nclaw_sdk/nclaw_sdk.dart';

final client = NclawClient(
  serverUrl: 'http://localhost:8080',
  jwt: Platform.environment['NCLAW_JWT']!
);

// List messages
final messages = await client.messages.list(topicId: 'topic-uuid');

// Create message
final newMsg = await client.messages.create(
  topicId: 'topic-uuid',
  content: 'Hello from Dart',
  role: 'user'
);
```

## Go

```go
package main

import (
	nclawsdk "github.com/nself-org/cli/sdk/go"
)

func main() {
	client := nclawsdk.NewClient(
		"http://localhost:8080",
		os.Getenv("NCLAW_JWT"),
	)

	msgs, err := client.Messages().List(ctx, nclawsdk.ListMessagesOpts{
		TopicID: "topic-uuid-here",
	})
	if err != nil {
		log.Fatal(err)
	}

	for _, msg := range msgs {
		fmt.Println(msg.Content)
	}
}
```

## Python

```python
from nclaw_sdk import NclawClient
import os

client = NclawClient(
    server_url="http://localhost:8080",
    jwt=os.getenv("NCLAW_JWT")
)

# List messages
messages = client.messages.list(topic_id="topic-uuid-here")

# Create message
new_msg = client.messages.create(
    topic_id="topic-uuid-here",
    content="Hello from Python",
    role="user"
)
```

## Environment variables

- `NCLAW_JWT`: authentication token (required for all SDKs)
- `NCLAW_SERVER`: server URL (defaults to `http://localhost:8080`)

All SDKs support passing credentials as constructor parameters or environment variables.
