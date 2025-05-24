import 'package:flutter/material.dart';
import 'package:namer_app/webrtc.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        final client = OpenAIRealtimeClient();
        client.init();
        return client;
      },
      child: MaterialApp(
        title: 'Namer App',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.greenAccent),
        ),
        home: MyHomePage(),
      ),
    );
  }
}

class MyHomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var openAIRealtimeClient = context.watch<OpenAIRealtimeClient>();

    return Scaffold(
        body: Text(
            openAIRealtimeClient.isConnected ? "Connected" : "Connecting..."));
  }
}
