class CustomerUpsertInput {
  const CustomerUpsertInput({
    required this.fullName,
    required this.phone,
    required this.email,
    required this.tier,
    required this.favoriteService,
    required this.hairProfile,
    required this.note,
  });

  final String fullName;
  final String phone;
  final String email;
  final String tier;
  final String favoriteService;
  final String hairProfile;
  final String note;
}
