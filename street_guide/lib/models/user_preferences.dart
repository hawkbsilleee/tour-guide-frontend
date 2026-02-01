class UserPreferences {
  final String userId;
  final String rawPreferences;
  final String enhancedPreferences;
  final String? createdAt;
  final String? updatedAt;

  UserPreferences({
    required this.userId,
    required this.rawPreferences,
    required this.enhancedPreferences,
    this.createdAt,
    this.updatedAt,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      userId: json['user_id'],
      rawPreferences: json['raw_preferences'],
      enhancedPreferences: json['enhanced_preferences'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'raw_preferences': rawPreferences,
      'enhanced_preferences': enhancedPreferences,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}
