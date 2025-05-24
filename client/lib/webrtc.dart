import 'package:flutter_webrtc/flutter_webrtc.dart';

late RTCPeerConnection _peerConnection;

Future<void> initConnection() async {
  final config = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ]
  };

  _peerConnection = await createPeerConnection(config);

  _peerConnection.onIceCandidate = (candidate) {
    // Send candidate to OpenAI if they support trickle ICE
  };

  _peerConnection.onTrack = (event) {
    // Handle incoming media tracks (if OpenAI sends any)
  };
}

Future<void> createAndSendOffer() async {
  final offer = await _peerConnection.createOffer({});
  await _peerConnection.setLocalDescription(offer);

  // Send offer.sdp to OpenAI's `/v1/real-time/` endpoint
}
