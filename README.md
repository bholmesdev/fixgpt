# FixGPT

> As seen at the [AI Engineer World's Fair](https://www.ai.engineer)

FixGPT makes ChatGPT easier to use. Have text *and* voice conversations at the same time like you're chatting with a friend on the phone. Plus, we make the right AI model selection depending on your ask.

## Development

This app includes both a `server/` and `client/` project.
- `server/` - a simple web server built with [Golang](https://golang.org/dl/). This handles key generation to connect to the OpenAI realtime API, and endpoints to hand off to a reasoning model for compelx queries.
- `client/` - the main application built with [Flutter](https://flutter.dev). This contains the entire mobile UI and can be compiled to your favorite platform (iOS, Android, Mac, Windows).

### Server setup

To set up the server, you will need an OpenAI API key. You can generate one by signing into your OpenAI account and [generating a key from the API platform console.](https://platform.openai.com/api-keys)

Once generated, place your API key in a `server/.env` file with the name `OPENAI_API_KEY` like so:

```sh
# .env
OPENAI_API_KEY=XXXX
```

### Client setup

This app is built using [Flutter](https://flutter.dev) and tested on iOS. To get started, I recommend following the ["Start building" guide](https://docs.flutter.dev/get-started/install/macos/mobile-ios) to set up your environment to use Flutter with the iOS simulator. If you are development on a Windows or Linux machine, try following [the "Start building" guide for Android](https://docs.flutter.dev/get-started/install/macos/mobile-android).

Once your environment is set up, you can run the application using the Run button in your IDE of choice.


