import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

class ChatMessage {
  final String content;
  final bool isThinking;
  final DateTime? thinkingStartTime;
  final int? thinkingDurationSeconds;

  ChatMessage({
    required this.content,
    this.isThinking = false,
    this.thinkingStartTime,
    this.thinkingDurationSeconds,
  });

  ChatMessage copyWith({
    String? content,
    bool? isThinking,
    DateTime? thinkingStartTime,
    int? thinkingDurationSeconds,
  }) {
    return ChatMessage(
      content: content ?? this.content,
      isThinking: isThinking ?? this.isThinking,
      thinkingStartTime: thinkingStartTime ?? this.thinkingStartTime,
      thinkingDurationSeconds:
          thinkingDurationSeconds ?? this.thinkingDurationSeconds,
    );
  }
}

class OpenAIRealtimeClient extends ChangeNotifier {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  MediaStream? _localStream;
  bool isConnected = false;
  bool chatEnabled = false;
  List<ChatMessage> messages = [];
  String? _currentReasoningCallId;
  DateTime? _reasoningStartTime;

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  void toggleChat() {
    chatEnabled = !chatEnabled;
    notifyListeners();
  }

  Future<void> _cleanup() async {
    await _localStream?.dispose();
    await _dataChannel?.close();
    await _peerConnection?.close();
  }

  Future<void> disconnect() async {
    developer.log('Disconnecting WebRTC connection');
    await _cleanup();
    _peerConnection = null;
    _dataChannel = null;
    _localStream = null;
    isConnected = false;
    notifyListeners();
  }

  Future<void> init() async {
    final ephemeralKey = await _getConnectionKey();
    developer.log("EphemeralKey: $ephemeralKey");

    try {
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
      await _sendSDP(offer, ephemeralKey);

      isConnected = true;
      notifyListeners();

      developer.log(
          'WebRTC connection established, waiting for session.created event');
    } catch (e) {
      developer.log('Error initializing connection: $e');
    }
  }

  Future<String> _getConnectionKey() async {
    final client = http.Client();

    final response = await client.get(
      Uri.parse('http://localhost:8080/session'),
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'Flutter-App',
      },
    ).timeout(Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to get connection key: ${response.statusCode}');
    }

    final data = json.decode(response.body);

    final key = data['key'];
    if (key == null || key.isEmpty) {
      throw Exception('No connection key received from server');
    }

    client.close();
    return key;
  }

  Future<void> _sendSDP(
      RTCSessionDescription offer, String ephemeralKey) async {
    const baseUrl = "https://api.openai.com/v1/realtime";
    const model = "gpt-4o-realtime-preview-2024-12-17";

    developer.log('Sending SDP to OpenAI API...');
    developer.log('SDP offer: ${offer.sdp?.substring(0, 100)}...');

    final client = HttpClient();
    try {
      final uri = Uri.parse('$baseUrl?model=$model');
      final request = await client.postUrl(uri);

      request.headers.removeAll('content-type');
      request.headers.set('authorization', 'Bearer $ephemeralKey');
      request.headers.set('content-type', 'application/sdp');

      request.write(offer.sdp ?? '');

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

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
  }

  void _handleMessage(RTCDataChannelMessage message) {
    // developer.log('Received message: ${message.text}');

    try {
      final messageData = json.decode(message.text);
      // developer.log('Parsed message: $messageData');

      switch (messageData['type']) {
        case 'session.created':
          developer.log('Session created, sending tool configuration');
          _sendToolCallConfig();

        case 'response.function_call_arguments.done':
          developer.log('Received function call arguments: $messageData');
          if (messageData['name'] == 'get_weather') {
            _handleWeatherToolCall(messageData);
          } else if (messageData['name'] == 'send_chat_message') {
            _handleSendChatMessageToolCall(messageData);
          } else if (messageData['name'] == 'ask_reasoning_model') {
            _handleReasoningModelToolCall(messageData);
          } else {
            developer.log('Unknown tool function: ${messageData['name']}');
          }

        case 'audio.response.started':
          developer.log("Model is responding...");

        case 'audio.response.completed':
          developer.log("Model response completed.");

        default:
          developer.log('Received message of type: ${messageData['type']}');
      }
    } catch (e) {
      developer.log('Error handling message: $e');
    }
  }

  Future<void> _handleSendChatMessageToolCall(
      Map<String, dynamic> toolCall) async {
    developer.log(
        'Processing send_chat_message tool call with ID: ${toolCall['call_id']}');

    final args = json.decode(toolCall['arguments']);
    final message = args['message'];
    if (message == null || message is! String) {
      developer.log('Invalid message in send_chat_message tool call');
      return;
    }
    developer.log('Sending chat message: $message');
    messages.add(ChatMessage(content: message));
    notifyListeners();
  }

  Future<void> _handleWeatherToolCall(Map<String, dynamic> message) async {
    developer
        .log('Processing get_weather tool call with ID: ${message['call_id']}');

    try {
      final args = json.decode(message['arguments']);
      developer.log('Tool call arguments: $args');

      final response = await http.post(
        Uri.parse('http://localhost:8080/tools/getWeather'),
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
        'output': e.toString(),
      };
      _dataChannel?.send(RTCDataChannelMessage(json.encode(errorResponse)));
    }
  }

  Future<void> _handleReasoningModelToolCall(
      Map<String, dynamic> toolCall) async {
    developer.log(
        'Processing ask_reasoning_model tool call with ID: ${toolCall['call_id']}');

    try {
      final args = json.decode(toolCall['arguments']);
      final details = args['details'];
      if (details == null || details is! String) {
        developer.log('Invalid details in ask_reasoning_model tool call');
        return;
      }

      developer.log('Sending request to reasoning model: $details');

      // Add "Thinking..." message and track timing
      _currentReasoningCallId = toolCall['call_id'];
      _reasoningStartTime = DateTime.now();
      messages.add(ChatMessage(
        content: "Thinking...",
        isThinking: true,
        thinkingStartTime: _reasoningStartTime,
      ));
      notifyListeners();

      final response = await http.post(
        Uri.parse('http://localhost:8080/reasoning'),
        headers: {
          'Content-Type': 'text/plain',
        },
        body: details,
      );

      if (response.statusCode != 200) {
        throw Exception('Reasoning API error: ${response.statusCode}');
      }

      final reasoningResponse = response.body;
      developer.log(
          'Reasoning model response received: ${reasoningResponse.substring(0, 100)}...');

      // Calculate thinking duration and update the thinking message
      final thinkingDuration = _reasoningStartTime != null
          ? DateTime.now().difference(_reasoningStartTime!).inSeconds
          : 0;

      // Remove the "Thinking..." message and add the response with duration info
      if (messages.isNotEmpty && messages.last.isThinking) {
        messages.removeLast();
      }

      messages.add(ChatMessage(
        content: reasoningResponse,
        thinkingDurationSeconds: thinkingDuration,
      ));

      // Clear tracking variables
      _currentReasoningCallId = null;
      _reasoningStartTime = null;
      notifyListeners();

      // Send function call output
      _dataChannel?.send(RTCDataChannelMessage(json.encode({
        'type': 'conversation.item.create',
        'item': {
          'type': 'function_call_output',
          'call_id': toolCall['call_id'],
          'output': reasoningResponse,
        },
      })));

      // Request response creation
      _dataChannel?.send(RTCDataChannelMessage(json.encode({
        'type': 'response.create',
      })));
    } catch (e) {
      developer.log('Error processing reasoning model tool call: $e');

      // Remove thinking message on error
      if (messages.isNotEmpty && messages.last.isThinking) {
        messages.removeLast();
      }

      // Add error message
      messages.add(ChatMessage(
        content: 'Error calling reasoning model: $e',
      ));

      // Clear tracking variables
      _currentReasoningCallId = null;
      _reasoningStartTime = null;
      notifyListeners();

      // Send error response
      _dataChannel?.send(RTCDataChannelMessage(json.encode({
        'type': 'conversation.item.create',
        'item': {
          'type': 'function_call_output',
          'call_id': toolCall['call_id'],
          'output': 'Error calling reasoning model: $e',
        },
      })));

      // Request response creation
      _dataChannel?.send(RTCDataChannelMessage(json.encode({
        'type': 'response.create',
      })));
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
            'name': 'send_chat_message',
            'description':
                'Send a chat message to the user. When using this tool, say that you are sending a chat message. Use this to send details that are easier to explain via text than voice. This includes links and drafts.',
            'parameters': {
              'type': 'object',
              'properties': {
                'message': {
                  'type': 'string',
                  'description': 'The message to send to the user',
                },
              },
              'required': ['message'],
            },
          },
          {
            'type': 'function',
            'name': 'ask_reasoning_model',
            'description':
                'When the user wants to go deeper into a topic, ask the reasoning model for more details. Speak a brief summary of the response and ask the user to reference the chat for more details. Common phrases include "give pros and cons," "give me more details," "go deeper," etc.',
            'parameters': {
              'type': 'object',
              'properties': {
                'details': {
                  'type': 'string',
                  'description': 'The details to send to the reasoning model',
                },
              },
              'required': ['details'],
            },
          },
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
  }
}
