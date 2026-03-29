import 'package:flutter/material.dart';

class CommunitySeedMessage {
  const CommunitySeedMessage({
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.minutesAgo,
  });

  final String senderId;
  final String senderName;
  final String message;
  final int minutesAgo;
}

class CommunityModel {
  const CommunityModel({
    required this.id,
    required this.name,
    required this.topic,
    required this.description,
    required this.tags,
    required this.icon,
    required this.color,
    required this.memberCount,
    required this.seedMessages,
  });

  final String id;
  final String name;
  final String topic;
  final String description;
  final List<String> tags;
  final IconData icon;
  final Color color;
  final int memberCount;
  final List<CommunitySeedMessage> seedMessages;
}
