import 'package:flutter/material.dart';
class ChannelScreen extends StatelessWidget {
  final String serverId;
  final String channelId;
  const ChannelScreen({super.key, required this.serverId, required this.channelId});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Channel $channelId')),
    body: Center(child: Text('Server: $serverId')),
  );
}
