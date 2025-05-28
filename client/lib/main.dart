import 'package:flutter/material.dart';
import 'package:namer_app/webrtc.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

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
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.grey),
        ),
        home: Home(),
      ),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final PanelController _panelController = PanelController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FixGPT'),
        centerTitle: true,
      ),
      body: SlidingUpPanel(
        controller: _panelController,
        defaultPanelState: PanelState.CLOSED,
        minHeight: 0,
        maxHeight: MediaQuery.of(context).size.height -
            MediaQuery.of(context).padding.top -
            kToolbarHeight -
            8.0,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24.0),
          topRight: Radius.circular(24.0),
        ),
        panel: ChatPane(panelController: _panelController),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Orb(),
            ActionButtons(panelController: _panelController),
          ],
        ),
      ),
    );
  }
}

class ActionButtons extends StatelessWidget {
  final PanelController panelController;

  const ActionButtons({super.key, required this.panelController});

  @override
  Widget build(BuildContext context) {
    var voice = context.watch<OpenAIRealtimeClient>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0, top: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            context,
            'assets/icons/chat_3_fill.svg',
            'Chat',
            () {
              voice.toggleChat();
              panelController.open();
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
  final PanelController panelController;

  const ChatPane({super.key, required this.panelController});

  @override
  Widget build(BuildContext context) {
    var voice = context.watch<OpenAIRealtimeClient>();
    var theme = Theme.of(context);

    return Column(
      children: [
        // Drag handle
        Container(
          height: 5,
          width: 40,
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(10),
          ),
        ),

        // Header with title and close button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Chat',
                style: theme.textTheme.titleLarge,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  panelController.close();
                },
              ),
            ],
          ),
        ),

        // Divider
        Divider(color: Colors.grey[300]),

        // Chat messages
        Expanded(
          child: voice.messages.isEmpty
              ? Center(
                  child: Text(
                    'No messages yet',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: voice.messages.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 10.0,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(18.0),
                          ),
                          child: MarkdownBody(
                            data: voice.messages[index],
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(
                                color: Colors.white,
                                fontSize: 16.0,
                              ),
                              a: const TextStyle(
                                color: Colors.lightBlue,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            onTapLink: (text, href, title) {
                              if (href != null) {
                                launchUrl(Uri.parse(href));
                              }
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
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
    return Column(
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
        const SizedBox(height: 16),
        Text(
          'Ask me anything',
          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
        ),
        const SizedBox(height: 30),
      ],
    );
  }
}
