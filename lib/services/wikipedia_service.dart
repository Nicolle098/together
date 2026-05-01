import 'dart:convert'; // Imports Dart's built-in tools for JSON decoding and UTF-8 text decoding.
import 'dart:io'; // Imports Dart's I/O library, which provides HttpClient for making raw HTTP requests.

/// Fetches plain-text summaries from the Wikipedia REST API.
///
/// Used as an Agent Skill to ground Gemma answers in factual content.
/// All calls are direct device-to-Wikipedia — no backend involved.
class WikipediaService { // Defines the class that handles all Wikipedia lookups.
  WikipediaService._(); // A private constructor — this prevents anyone from creating an instance; all methods are static (called on the class itself).

  static const _baseUrl = 'en.wikipedia.org'; // The base domain for all Wikipedia API calls.
  static const _userAgent = 'TogetherApp/1.0 (offline-safety-app)'; // The User-Agent header we send with requests so Wikipedia knows which app is calling.

  /// Returns the first ~3 sentences of the Wikipedia article most relevant
  /// to [query], or null if nothing is found or an error occurs.
  static Future<WikiResult?> search(String query) async { // A static async method that takes a search query and returns a WikiResult (or null on failure).
    try { // Wraps all network logic in try/catch so errors silently return null instead of crashing.
      // Step 1: OpenSearch to find the canonical article title.
      final searchUri = Uri.https(_baseUrl, '/w/api.php', { // Builds the Wikipedia OpenSearch API URL with query parameters.
        'action': 'opensearch', // Tells the Wikipedia API we want to use its OpenSearch endpoint.
        'search': query, // The search term provided by the caller.
        'limit': '1', // We only want the single best-matching article title.
        'format': 'json', // Asks Wikipedia to return the response as JSON.
      });

      final client = HttpClient(); // Creates a low-level HTTP client for making the network requests.
      client.connectionTimeout = const Duration(seconds: 5); // Sets a 5-second timeout so the app doesn't hang if Wikipedia is slow.

      final searchReq = await client.getUrl(searchUri); // Opens a GET request to the OpenSearch URL.
      searchReq.headers.set(HttpHeaders.userAgentHeader, _userAgent); // Attaches our app's User-Agent header to the request.
      final searchRes = await searchReq.close(); // Sends the request and waits for the server's response.
      if (searchRes.statusCode != 200) return null; // If the response isn't a success (200 OK), give up and return null.

      final searchBody =
          await searchRes.transform(const Utf8Decoder()).join(); // Reads the full response body as a UTF-8 encoded string.
      final searchJson = jsonDecode(searchBody) as List<dynamic>; // Parses the JSON string into a Dart List.

      final titles = searchJson[1] as List<dynamic>; // The second element of the OpenSearch response is the list of matched article titles.
      if (titles.isEmpty) return null; // If no articles were found, return null.

      final title = titles.first as String; // Takes the very first (best-matching) article title.

      // Step 2: Fetch the page summary.
      final summaryUri = Uri.https( // Builds the Wikipedia REST API URL to fetch the article summary.
        _baseUrl,
        '/api/rest_v1/page/summary/${Uri.encodeComponent(title)}', // URL-encodes the title so special characters (spaces, accents) are handled correctly.
      );

      final summaryReq = await client.getUrl(summaryUri); // Opens a GET request to the summary API endpoint.
      summaryReq.headers.set(HttpHeaders.userAgentHeader, _userAgent); // Attaches our User-Agent header to this request as well.
      final summaryRes = await summaryReq.close(); // Sends the request and waits for the response.
      if (summaryRes.statusCode != 200) return null; // Returns null if the summary request failed.

      final summaryBody =
          await summaryRes.transform(const Utf8Decoder()).join(); // Reads the full summary response body as a UTF-8 string.
      final summaryJson =
          jsonDecode(summaryBody) as Map<String, dynamic>; // Parses the JSON string into a Dart Map (key-value pairs).

      client.close(); // Closes the HTTP client to release the network connection.

      final extract = summaryJson['extract'] as String?; // Reads the article's plain-text extract (the human-readable summary) from the JSON.
      final pageTitle = summaryJson['title'] as String? ?? title; // Reads the article's display title; falls back to the search title if not present.
      final pageUrl = (summaryJson['content_urls'] // Reads the mobile page URL from the nested JSON structure.
              as Map<String, dynamic>?)?['mobile']?['page'] as String? ??
          'https://en.wikipedia.org/wiki/${Uri.encodeComponent(title)}'; // Falls back to constructing a standard Wikipedia URL if the API didn't return one.

      if (extract == null || extract.isEmpty) return null; // Returns null if there's no readable text in the article.

      // Trim to ~300 chars to avoid overwhelming the model context.
      final trimmed =
          extract.length > 300 ? '${extract.substring(0, 300)}…' : extract; // If the extract is longer than 300 characters, cuts it short and appends '…'; otherwise keeps it as-is.

      return WikiResult(title: pageTitle, summary: trimmed, url: pageUrl); // Packages the title, summary, and URL into a WikiResult object and returns it.
    } catch (_) { // Catches any exception (network error, parse error, etc.) without naming it.
      return null; // Silently returns null on any failure — the caller will handle the missing result.
    }
  }
}

class WikiResult { // Defines a simple data class to hold the three pieces of information we want from a Wikipedia article.
  const WikiResult({ // A constant constructor — WikiResult objects are immutable once created.
    required this.title, // The article's title is required.
    required this.summary, // The trimmed plain-text summary is required.
    required this.url, // The URL to the Wikipedia page is required.
  });
  final String title; // Stores the Wikipedia article title.
  final String summary; // Stores the plain-text summary (max 300 characters).
  final String url; // Stores the URL to the full Wikipedia article.
}
