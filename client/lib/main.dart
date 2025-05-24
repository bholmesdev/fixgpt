import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;

class OpenAIRealtimeClient extends StatefulWidget {
  @override
  _OpenAIRealtimeClientState createState() => _OpenAIRealtimeClientState();
}

class _OpenAIRealtimeClientState extends State<OpenAIRealtimeClient> {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  MediaStream? _localStream;
  String _status = 'Initializing...';
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _initializeConnection();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  Future<void> _cleanup() async {
    await _localStream?.dispose();
    await _dataChannel?.close();
    await _peerConnection?.close();
  }

  Future<void> _initializeConnection() async {
    try {
      // Get ephemeral key from your server
      developer.log('Requesting session token from server...');

      // Create HTTP client with custom settings
      final client = http.Client();

      final tokenResponse = await client.get(
        Uri.parse('http://localhost:8080/session'),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Flutter-App',
        },
      ).timeout(Duration(seconds: 10));

      developer.log('Server response status: ${tokenResponse.statusCode}');
      developer.log('Server response headers: ${tokenResponse.headers}');
      developer.log('Server response body: ${tokenResponse.body}');

      if (tokenResponse.statusCode != 200) {
        throw Exception(
            'Failed to get session token: ${tokenResponse.statusCode}');
      }

      final data = json.decode(tokenResponse.body);
      developer.log('Parsed token data: $data');

      final ephemeralKey = data['key'];
      if (ephemeralKey == null || ephemeralKey.isEmpty) {
        throw Exception('No ephemeral key received from server');
      }

      developer.log('Got ephemeral key: ${ephemeralKey.substring(0, 10)}...');
      client.close();

      // Create peer connection
      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      };

      _peerConnection = await createPeerConnection(configuration);

      // Set up audio handling
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        developer.log('Received remote track');
        // The audio will be played automatically by the WebRTC implementation
      };

      // Get user media (microphone)
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });

      // Add local stream to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Create data channel for events
      RTCDataChannelInit dataChannelDict = RTCDataChannelInit();
      _dataChannel = await _peerConnection!
          .createDataChannel('oai-events', dataChannelDict);

      _dataChannel!.onMessage = _handleMessage;
      _dataChannel!.onDataChannelState = (RTCDataChannelState state) {
        developer.log('Data channel state changed: $state');
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          developer.log('Data channel opened');
        }
      };

      // Create offer and set local description
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Send SDP to OpenAI Realtime API
      const baseUrl = "https://api.openai.com/v1/realtime";
      const model = "gpt-4o-realtime-preview-2024-12-17";

      developer.log('Sending SDP to OpenAI API...');
      developer.log('SDP offer: ${offer.sdp?.substring(0, 100)}...');

      final httpClient = HttpClient();
      try {
        final uri = Uri.parse('$baseUrl?model=$model');
        final request = await httpClient.postUrl(uri);

        request.headers.removeAll('content-type');
        request.headers.set('authorization', 'Bearer $ephemeralKey');
        request.headers.set('content-type', 'application/sdp');

        request.write(offer.sdp ?? '');

        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();

        developer.log('OpenAI API response status: ${response.statusCode}');
        developer.log('OpenAI API response headers: ${response.headers}');
        developer.log('OpenAI API response body: $responseBody');

        if (response.statusCode > 299) {
          throw Exception(
              'Failed to establish WebRTC connection with OpenAI. Status: ${response.statusCode}, Body: $responseBody');
        }

        // Set remote description with the response
        final answer = RTCSessionDescription(
          responseBody,
          'answer',
        );
        await _peerConnection!.setRemoteDescription(answer);
      } finally {
        client.close();
      }

      setState(() {
        _status = 'Connected! Waiting for session creation...';
        _isConnected = true;
      });

      developer.log(
          'WebRTC connection established, waiting for session.created event');
    } catch (e) {
      developer.log('Error initializing connection: $e');
      setState(() {
        _status = 'Connection failed: $e';
      });
    }
  }

  void _handleMessage(RTCDataChannelMessage message) {
    developer.log('Received message: ${message.text}');

    try {
      final messageData = json.decode(message.text);
      developer.log('Parsed message: $messageData');

      switch (messageData['type']) {
        case 'session.created':
          developer.log('Session created, sending tool configuration');
          _sendToolCallConfig();
          break;

        case 'response.function_call_arguments.done':
          developer.log('Received function call arguments: $messageData');
          if (messageData['name'] == 'get_weather') {
            _handleWeatherToolCall(messageData);
          } else {
            developer.log('Unknown tool function: ${messageData['name']}');
          }
          break;

        case 'audio.response.started':
          setState(() {
            _status = 'AI is responding...';
          });
          break;

        case 'audio.response.completed':
          setState(() {
            _status = 'Response completed. Try asking about the weather!';
          });
          break;

        default:
          developer.log('Received message of type: ${messageData['type']}');
      }
    } catch (e) {
      developer.log('Error handling message: $e');
    }
  }

  Future<void> _handleWeatherToolCall(Map<String, dynamic> message) async {
    developer
        .log('Processing get_weather tool call with ID: ${message['call_id']}');

    try {
      final args = json.decode(message['arguments']);
      developer.log('Tool call arguments: $args');

      final response = await http.post(
        Uri.parse('http://192.168.1.100:8080/tools/getWeather'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'location': args['location'],
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Weather API error: ${response.statusCode}');
      }

      final weatherData = json.decode(response.body);
      developer.log('Weather data received: $weatherData');

      final output = '${weatherData['temperature']}${weatherData['units']}';

      // Send function call output
      _dataChannel?.send(RTCDataChannelMessage(json.encode({
        'type': 'conversation.item.create',
        'item': {
          'type': 'function_call_output',
          'call_id': message['call_id'],
          'output': output,
        },
      })));

      // Request response creation
      _dataChannel?.send(RTCDataChannelMessage(json.encode({
        'type': 'response.create',
      })));
    } catch (e) {
      developer.log('Error processing tool call: $e');

      final errorResponse = {
        'type': 'tool_response',
        'tool_call_id': message['call_id'],
        'output': 'Error: ${e.toString()}',
      };
      _dataChannel?.send(RTCDataChannelMessage(json.encode(errorResponse)));
    }
  }

  void _sendToolCallConfig() {
    developer.log('Sending session.update with tool configuration');

    final toolConfig = {
      'type': 'session.update',
      'session': {
        'tools': [
          {
            'type': 'function',
            'name': 'get_weather',
            'description': 'Get the current weather in a given location',
            'parameters': {
              'type': 'object',
              'properties': {
                'location': {
                  'type': 'string',
                  'description': 'The name of the city to get the weather for',
                },
              },
              'required': ['location'],
            },
          },
        ],
      },
    };

    _dataChannel?.send(RTCDataChannelMessage(json.encode(toolConfig)));

    setState(() {
      _status = 'Session updated with tools. Try asking about the weather!';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('OpenAI Realtime API'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isConnected ? Colors.green[100] : Colors.orange[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isConnected ? Colors.green : Colors.orange,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isConnected ? Icons.check_circle : Icons.pending,
                    color: _isConnected ? Colors.green : Colors.orange,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "working",
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Instructions:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '1. Make sure your microphone permissions are granted\n'
              '2. Wait for the connection to be established\n'
              '3. Speak to the AI and ask about the weather in any city\n'
              '4. The AI will respond with audio',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            if (_isConnected)
              ElevatedButton(
                onPressed: _initializeConnection,
                child: Text('Reconnect'),
              ),
          ],
        ),
      ),
    );
  }
}

// Main app
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenAI Realtime API Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: OpenAIRealtimeClient(),
    );
  }
}

void main() {
  runApp(MyApp());
}
