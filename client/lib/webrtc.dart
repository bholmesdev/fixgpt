import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

class OpenAIRealtimeClient extends ChangeNotifier {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  MediaStream? _localStream;
  bool isConnected = false;

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

        case 'response.function_call_arguments.done':
          developer.log('Received function call arguments: $messageData');
          if (messageData['name'] == 'get_weather') {
            _handleWeatherToolCall(messageData);
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
  }
}
