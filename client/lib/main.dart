import 'package:flutter/material.dart';
import 'package:namer_app/webrtc.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => OpenAIRealtimeClient(),
      child: MaterialApp(
        title: 'FixGPT',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.greenAccent),
        ),
        home: Home(),
      ),
    );
  }
}

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    var voice = context.watch<OpenAIRealtimeClient>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('FixGPT'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Orb(),
          ActionButtons(),
        ],
      ),
    );
  }
}

class ActionButtons extends StatelessWidget {
  const ActionButtons({super.key});

  @override
  Widget build(BuildContext context) {
    var voice = context.watch<OpenAIRealtimeClient>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 32.0, top: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            context,
            'assets/icons/chat_3_fill.svg',
            'Chat',
            () {
              // TODO: Implement Chat button action
              print('Chat button pressed');
            },
          ),
          _buildActionButton(
            context,
            'assets/icons/phone_fill.svg',
            'Voice',
            () {
              voice.init();
              print('Voice button pressed');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, String iconPath, String label,
      VoidCallback onPressed) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: CircleAvatar(
              radius: 30,
              backgroundColor: Colors.grey[300],
              child: SvgPicture.asset(iconPath,
                  width: 30,
                  height: 30,
                  colorFilter:
                      const ColorFilter.mode(Colors.black, BlendMode.srcIn))),
        ),
        const SizedBox(height: 8),
        Text(label),
      ],
    );
  }
}

class ChatPane extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var voice = context.watch<OpenAIRealtimeClient>();
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: voice.messages.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 10.0,
              ),
              decoration: BoxDecoration(
                color: Colors.blue[500],
                borderRadius: BorderRadius.circular(18.0),
              ),
              child: Text(
                voice.messages[index],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16.0,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class Orb extends StatelessWidget {
  const Orb({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var voice = context.watch<OpenAIRealtimeClient>();
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutQuad,
              width: voice.isConnected ? 200 : 150,
              height: voice.isConnected ? 200 : 150,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: voice.isConnected
                      ? [
                          Colors.blue[400]!,
                          Colors.blue[600]!,
                        ]
                      : [
                          Colors.grey[400]!,
                          Colors.grey[600]!,
                        ],
                ),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Ask me anything',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
