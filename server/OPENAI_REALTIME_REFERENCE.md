

Send tool call config from client. Must be called AFTER session.create is fired

```js
dc.send(JSON.stringify({
    type: "session.update",
    session: {
        tools: [{
            type: "function",
            name: "get_weather",
            description: "Get the current weather in a given location",
            parameters: {
                type: "object",
                properties: {
                    location: {
                        type: "string",
                        description: "The name of the city to get the weather for"
                    }
                },
                required: ["location"]
            }
        }]
    }
}));
```

When OpenAI requests a tool call
```json
{
  "type": "response.function_call_arguments.done",
  "name": "get_weather",
  "arguments": "{"location":"PLACE"}"
}
```

Respond to a tool call

```js
dc.send(JSON.stringify({
    type: "conversation.item.create",
    item: {
        type: "function_call_output",
        call_id: message.call_id,
        output: `${TEMP}${UNITS}`
    }
}));
```