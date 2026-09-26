import '../../domain/account.dart';
import '../api/notes_api_client.dart';

/// Where the signed-in account + OctoCredits balance comes from.
abstract interface class AccountRepository {
  Future<NotesAccount> me();
}

/// `GET /v1/me` on `octonotes-api`.
class ApiAccountRepository implements AccountRepository {
  const ApiAccountRepository(this._client);

  final NotesApiClient _client;

  @override
  Future<NotesAccount> me() async => NotesAccount.fromJson(await _client.getJson('/v1/me'));
}

/// Offline default (no backend configured, and tests).
class InMemoryAccountRepository implements AccountRepository {
  const InMemoryAccountRepository([this.account = NotesAccount.guest]);

  final NotesAccount account;

  @override
  Future<NotesAccount> me() async => account;
}
