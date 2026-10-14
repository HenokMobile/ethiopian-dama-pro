// ============================================================================
//  የኢትዮጵያ ዳማ Pro — Ethiopian Dama / Checkers Pro
//  ---------------------------------------------------------------------------
//  A production-ready Flutter implementation of the Ethiopian variant of
//  draughts ("Dama"), including:
//
//    * Authentic Ethiopian Dama rules (flying kings, 4-way pawn capture,
//      mandatory multi-jumps, mid-capture promotion).
//    * The traditional "Yifuta" (huffing) system with Burn / Force / Ignore
//      decisions, plus a strict mandatory-capture mode.
//    * A Grandmaster minimax AI with alpha-beta pruning, move ordering,
//      quiescence search and iterative deepening, running inside a Dart
//      isolate via compute() so the UI never freezes.
//    * Pass & Play, and fully offline Wi-Fi/Hotspot TCP multiplayer on
//      port 4545 with move / yifuta / rematch / chat synchronization.
//    * Bilingual UI (Amharic default, English toggle), haptic feedback,
//      undo, captured-piece counters and a hand-crafted wooden dark theme.
//
//  Board representation: 64-int list. Squares are indexed 0..63
//  (row = index ~/ 8, col = index % 8). Pieces live only on dark squares
//  ((row + col) % 2 == 1). Piece encoding:
//      0 = empty, 1 = white pawn, 2 = white king,
//      3 = black pawn, 4 = black king.
//  White (Player 1 / Human / bottom) starts on rows 5..7 and moves toward
//  row 0. Black (Player 2 / AI / top) starts on rows 0..2 and moves toward
//  row 7.
//
//  Single-file project: this file is intentionally self-contained so the
//  Android shell can be regenerated with `flutter create .` in CI.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ----------------------------------------------------------------------------
// Enums
// ----------------------------------------------------------------------------

enum AppLanguage { amharic, english }

enum PawnCaptureMode { fourWay, forwardOnly }

enum YifutaMode { traditional, strict }

enum Difficulty { easy, medium, grandmaster }

enum GameMode { vsAi, passPlay, hotspot }

// ----------------------------------------------------------------------------
// Localization (Amharic default)
// ----------------------------------------------------------------------------

/// Global language notifier so the whole app rebuilds when the user toggles
/// Amharic / English from the settings screen or the home screen.
final ValueNotifier<AppLanguage> languageNotifier =
    ValueNotifier<AppLanguage>(AppLanguage.amharic);

class S {
  static AppLanguage lang = AppLanguage.amharic;

  static bool get isAm => lang == AppLanguage.amharic;

  static String t(String key) {
    final entry = _data[key];
    if (entry == null) return key;
    return entry[lang] ?? entry[AppLanguage.english] ?? key;
  }

  static const Map<String, Map<AppLanguage, String>> _data = {
    // ---- General / home -----------------------------------------------------
    'appTitle': {
      AppLanguage.amharic: 'የኢትዮጵያ ዳማ Pro',
      AppLanguage.english: 'Ethiopian Dama Pro',
    },
    'tagline': {
      AppLanguage.amharic: 'የአዕምሮና ስትራቴጂ የሆነ ባህላዊ ጨዋታ',
      AppLanguage.english: 'The classic game of mind & strategy',
    },
    'version': {
      AppLanguage.amharic: 'ቅጂ 1.0.0 • ከመስመር ውጭ (offline) • ያለ ማስታወሻ',
      AppLanguage.english: 'v1.0.0 • fully offline • no ads',
    },
    'vsAi': {
      AppLanguage.amharic: 'ከኮምፒውተር ጋር',
      AppLanguage.english: 'Vs Computer',
    },
    'vsAiSub': {
      AppLanguage.amharic: 'ከጠንካራው የዳማ አውራ AI ጋር ተዋጋ',
      AppLanguage.english: 'Battle the Grandmaster AI',
    },
    'passPlay': {
      AppLanguage.amharic: 'ለሁለት በአንድ ስልክ',
      AppLanguage.english: 'Pass & Play (2 players)',
    },
    'passPlaySub': {
      AppLanguage.amharic: 'ከጓደኛህ ጋር በተመሳሳይ ስልክ ላይ',
      AppLanguage.english: 'Play a friend on one device',
    },
    'hotspot': {
      AppLanguage.amharic: 'በHotspot ለሁለት ስልክ',
      AppLanguage.english: 'Offline Hotspot 2-Player',
    },
    'hotspotSub': {
      AppLanguage.amharic: 'ያለ ኢንተርኔት — በWi-Fi/Hotspot TCP',
      AppLanguage.english: 'No internet — local Wi-Fi P2P',
    },
    'settings': {
      AppLanguage.amharic: 'ቅንብሮች',
      AppLanguage.english: 'Settings',
    },
    'settingsSub': {
      AppLanguage.amharic: 'የጨዋታ ህጎች፣ የውድድር ደረጃ፣ ቋንቋ',
      AppLanguage.english: 'Rules, difficulty, language',
    },
    // ---- Settings -----------------------------------------------------------
    'difficulty': {
      AppLanguage.amharic: 'የውድድር ደረጃ',
      AppLanguage.english: 'Difficulty',
    },
    'chooseDifficulty': {
      AppLanguage.amharic: 'የውድድር ደረጃ ምረጥ',
      AppLanguage.english: 'Choose difficulty',
    },
    'easy': {
      AppLanguage.amharic: 'ጀማሪ',
      AppLanguage.english: 'Beginner',
    },
    'easySub': {
      AppLanguage.amharic: 'ቀላል ስሌት + ዘፈቀመ አመራር (Depth 2)',
      AppLanguage.english: 'Light search with randomness (depth 2)',
    },
    'medium': {
      AppLanguage.amharic: 'መካከለኛ',
      AppLanguage.english: 'Medium',
    },
    'mediumSub': {
      AppLanguage.amharic: 'ጥልቅ ስሌት (Depth 4)',
      AppLanguage.english: 'Deep evaluation (depth 4)',
    },
    'grandmaster': {
      AppLanguage.amharic: 'የዳማ አውራ',
      AppLanguage.english: 'Grandmaster',
    },
    'grandmasterSub': {
      AppLanguage.amharic: 'እጅግ ጠንካራ ስሌት (Depth 7–8)',
      AppLanguage.english: 'Brutal search (depth 7–8)',
    },
    'yifutaMode': {
      AppLanguage.amharic: 'የይፉታ ስርዓት',
      AppLanguage.english: 'Yifuta (huffing) rule',
    },
    'yifutaTraditional': {
      AppLanguage.amharic: 'ባህላዊ ይፉታ (ነባሪ)',
      AppLanguage.english: 'Traditional Yifuta (default)',
    },
    'yifutaTraditionalSub': {
      AppLanguage.amharic: 'መብላትን ካልፈጸምክ — ተቃዋሚው ቅጣቱን ይምረጣል',
      AppLanguage.english: 'Miss a capture and your opponent punishes you',
    },
    'yifutaStrict': {
      AppLanguage.amharic: 'የግዴታ መብላት',
      AppLanguage.english: 'Strict mandatory capture',
    },
    'yifutaStrictSub': {
      AppLanguage.amharic: 'መብላት ሲቻል መብላት ግዴታ ነው',
      AppLanguage.english: 'Captures are forced whenever available',
    },
    'pawnCaptureDir': {
      AppLanguage.amharic: 'የተራ ጠጠር መብላት አቅጣጫ',
      AppLanguage.english: 'Pawn capture direction',
    },
    'fourWay': {
      AppLanguage.amharic: '4-አቅጣጫ (ነባሪ)',
      AppLanguage.english: '4-Way (default)',
    },
    'fourWaySub': {
      AppLanguage.amharic: 'ተራ ጠጠር ወደ 4ዱም አቅጣጫ መብላት ይችላል',
      AppLanguage.english: 'Pawns capture forward and backward',
    },
    'forwardOnly': {
      AppLanguage.amharic: 'ወደፊት ብቻ',
      AppLanguage.english: 'Forward-only',
    },
    'forwardOnlySub': {
      AppLanguage.amharic: 'ተራ ጠጠር ወደፊት ብቻ ይበላል',
      AppLanguage.english: 'Pawns capture forward only',
    },
    'haptics': {
      AppLanguage.amharic: 'የእጅ ስሜት (Haptic)',
      AppLanguage.english: 'Haptic feedback',
    },
    'hapticsSub': {
      AppLanguage.amharic: 'በየእርምጃው መታጠፍ/መምታት ብርቭት',
      AppLanguage.english: 'Vibration on moves and captures',
    },
    'language': {
      AppLanguage.amharic: 'ቋንቋ',
      AppLanguage.english: 'Language',
    },
    'amharic': {
      AppLanguage.amharic: 'አማርኛ',
      AppLanguage.english: 'Amharic',
    },
    'english': {
      AppLanguage.amharic: 'English',
      AppLanguage.english: 'English',
    },
    // ---- Game status --------------------------------------------------------
    'yourTurn': {
      AppLanguage.amharic: 'ተራህ ነው!',
      AppLanguage.english: 'Your turn!',
    },
    'aiTurn': {
      AppLanguage.amharic: 'የAI ተራ…',
      AppLanguage.english: "AI's turn…",
    },
    'aiThinking': {
      AppLanguage.amharic: 'አውራው እያሰበ ነው…',
      AppLanguage.english: 'Grandmaster is thinking…',
    },
    'opponentTurn': {
      AppLanguage.amharic: 'የተቃዋሚው ተራ…',
      AppLanguage.english: "Opponent's turn…",
    },
    'turnWhite': {
      AppLanguage.amharic: 'ተራው የነጭ ነው',
      AppLanguage.english: "White's turn",
    },
    'turnBlack': {
      AppLanguage.amharic: 'ተራው የጥቁር ነው',
      AppLanguage.english: "Black's turn",
    },
    'white': {
      AppLanguage.amharic: 'ነጭ',
      AppLanguage.english: 'White',
    },
    'black': {
      AppLanguage.amharic: 'ጥቁር',
      AppLanguage.english: 'Black',
    },
    'you': {
      AppLanguage.amharic: 'አንተ',
      AppLanguage.english: 'You',
    },
    'ai': {
      AppLanguage.amharic: 'ኮምፒውተር',
      AppLanguage.english: 'Computer',
    },
    'opponent': {
      AppLanguage.amharic: 'ተቃዋሚ',
      AppLanguage.english: 'Opponent',
    },
    'remaining': {
      AppLanguage.amharic: 'ቀሪ ጠጠሮች',
      AppLanguage.english: 'pieces left',
    },
    // ---- Controls -----------------------------------------------------------
    'undo': {
      AppLanguage.amharic: 'መልስ',
      AppLanguage.english: 'Undo',
    },
    'newGame': {
      AppLanguage.amharic: 'አዲስ ጨዋታ',
      AppLanguage.english: 'New game',
    },
    'flipBoard': {
      AppLanguage.amharic: 'መገለበጥ',
      AppLanguage.english: 'Flip',
    },
    'resign': {
      AppLanguage.amharic: 'ማሰር',
      AppLanguage.english: 'Resign',
    },
    'banter': {
      AppLanguage.amharic: 'ውይይት',
      AppLanguage.english: 'Banter',
    },
    'confirm': {
      AppLanguage.amharic: 'አዎ',
      AppLanguage.english: 'Yes',
    },
    'cancel': {
      AppLanguage.amharic: 'ሰርዝ',
      AppLanguage.english: 'Cancel',
    },
    'accept': {
      AppLanguage.amharic: 'ተቀበል',
      AppLanguage.english: 'Accept',
    },
    'decline': {
      AppLanguage.amharic: 'አትቀበል',
      AppLanguage.english: 'Decline',
    },
    'nothingToUndo': {
      AppLanguage.amharic: 'ለመመለስ ምንም የለም',
      AppLanguage.english: 'Nothing to undo',
    },
    'undoNetDisabled': {
      AppLanguage.amharic: 'በአውታረ መስመር ጨዋታ መልስ (Undo) አይሠራም',
      AppLanguage.english: 'Undo is disabled in network games',
    },
    'confirmNewGame': {
      AppLanguage.amharic: 'አዲስ ጨዋታ መጀመር ትፈልጋለህ?',
      AppLanguage.english: 'Start a new game?',
    },
    'confirmResign': {
      AppLanguage.amharic: 'እርግጠኛ ነህ? አሰርተህ ከወጣህ ትሸከማለህ።',
      AppLanguage.english: 'Resign and lose the game?',
    },
    'gameStarted': {
      AppLanguage.amharic: 'ጨዋታ ተጀመረ!',
      AppLanguage.english: 'Game started!',
    },
    // ---- Yifuta -------------------------------------------------------------
    'yifutaTitle': {
      AppLanguage.amharic: 'ይፉታ! 🔥',
      AppLanguage.english: 'Yifuta! 🔥',
    },
    'yifutaPrompt': {
      AppLanguage.amharic: '{p} መብላትን ዘለለ! ቅጣቱን ምረጥ፦',
      AppLanguage.english: '{p} missed a capture! Choose the punishment:',
    },
    'yifutaBurn': {
      AppLanguage.amharic: 'ይፉታ ውሰድ / አቃጥል 🔥',
      AppLanguage.english: 'Huff — burn the piece 🔥',
    },
    'yifutaBurnSub': {
      AppLanguage.amharic: 'የዘለለውን ጠጠር ከሰሌዳው ላይ አስወግድ',
      AppLanguage.english: 'Remove the offending piece from the board',
    },
    'yifutaForce': {
      AppLanguage.amharic: 'በግድ አስበላ ↩️',
      AppLanguage.english: 'Force the capture ↩️',
    },
    'yifutaForceSub': {
      AppLanguage.amharic: 'እንቅስቃሱን ተመልሶ መብላት አስገድደው',
      AppLanguage.english: 'Rewind the move and force the capture',
    },
    'yifutaIgnore': {
      AppLanguage.amharic: 'ይለፍ ⏭️',
      AppLanguage.english: 'Ignore ⏭️',
    },
    'yifutaIgnoreSub': {
      AppLanguage.amharic: 'ያለ ቅጣት ቀጥል',
      AppLanguage.english: 'Let it slide this time',
    },
    'yifutaWaiting': {
      AppLanguage.amharic: 'ተቃዋሚው ይፉታ እያሰበ ነው…',
      AppLanguage.english: 'Opponent is deciding on Yifuta…',
    },
    'forcedBanner': {
      AppLanguage.amharic: 'በግድ አስበላ! መብላት አለብህ።',
      AppLanguage.english: 'Forced! You must capture.',
    },
    'mustCaptureHint': {
      AppLanguage.amharic: 'በግድ አስበላ — መብላት ብቻ!',
      AppLanguage.english: 'Mandatory — captures only!',
    },
    'aiBurned': {
      AppLanguage.amharic: 'AI ይፉታ ወስዷል! 🔥',
      AppLanguage.english: 'AI chose to huff! 🔥',
    },
    'aiForced': {
      AppLanguage.amharic: 'AI በግድ ብላ ብሎሃል! ↩️',
      AppLanguage.english: 'AI forces you to capture! ↩️',
    },
    'promotedToast': {
      AppLanguage.amharic: 'ንጉሥ ሆነ! 👑',
      AppLanguage.english: 'Promoted to King! 👑',
    },
    // ---- Game over ----------------------------------------------------------
    'youWin': {
      AppLanguage.amharic: 'አሸነፍህ! 🏆',
      AppLanguage.english: 'You win! 🏆',
    },
    'youLose': {
      AppLanguage.amharic: 'ተሸነፍህ! 😅',
      AppLanguage.english: 'You lose! 😅',
    },
    'whiteWins': {
      AppLanguage.amharic: 'ነጭ አሸነፈ! 🏆',
      AppLanguage.english: 'White wins! 🏆',
    },
    'blackWins': {
      AppLanguage.amharic: 'ጥቁር አሸነፈ! 🏆',
      AppLanguage.english: 'Black wins! 🏆',
    },
    'draw': {
      AppLanguage.amharic: 'ደብድብ — ተሻማችሁ! 🤝',
      AppLanguage.english: 'Draw! 🤝',
    },
    'drawSub': {
      AppLanguage.amharic: '60 እርምጃዎች ሳይበላና ሳይሻገር ተከታታይ ሆነዋል',
      AppLanguage.english: '60 consecutive quiet moves',
    },
    'wipeSub': {
      AppLanguage.amharic: 'የተቃዋሚውን ሁሉንም ወገን አጠፋ!',
      AppLanguage.english: 'Wiped out every opponent piece!',
    },
    'blockSub': {
      AppLanguage.amharic: 'ተቃዋሚው እንቅስቃሴ መስጠት አልቻለም!',
      AppLanguage.english: 'Opponent has no legal moves!',
    },
    'resignedSub': {
      AppLanguage.amharic: 'ተሸንፎ አሰርቶ ወጥቷል።',
      AppLanguage.english: 'Opponent resigned.',
    },
    'netEndedSub': {
      AppLanguage.amharic: 'መስመሩ ተቋርጧል — ጨዋታው አበቃ።',
      AppLanguage.english: 'The connection was lost.',
    },
    'opponentLeft': {
      AppLanguage.amharic: 'ተቃዋሪህ ገባ',
      AppLanguage.english: 'Opponent left',
    },
    'rematch': {
      AppLanguage.amharic: 'እንደገና ይጫወት',
      AppLanguage.english: 'Rematch',
    },
    'backToMenu': {
      AppLanguage.amharic: 'ወደ ዋናው ገጽ',
      AppLanguage.english: 'Back to menu',
    },
    // ---- Hotspot lobby ------------------------------------------------------
    'host': {
      AppLanguage.amharic: 'አስተናጋጅ (Host)',
      AppLanguage.english: 'Host',
    },
    'join': {
      AppLanguage.amharic: 'መገናኛ (Join)',
      AppLanguage.english: 'Join',
    },
    'hostTitle': {
      AppLanguage.amharic: 'ጨዋታ አስተናግድ',
      AppLanguage.english: 'Host a game',
    },
    'joinTitle': {
      AppLanguage.amharic: 'ወደ ጨዋታ አገናኝ',
      AppLanguage.english: 'Join a game',
    },
    'hostInstructions': {
      AppLanguage.amharic:
          '1) በዚህ ስልክ ላይ Hotspot አብራ (ወይም Wi-Fi አጋራ)።\n2) በጓደኛህ ስልክ ወደ አውታረሱ አገናኝ።\n3) ከታች የሚታየውን IP አድራሻ ለጓደኛህ አስገባ እንዲጫወት።',
      AppLanguage.english:
          '1) Enable Hotspot (or share Wi-Fi) on this phone.\n2) Connect the other phone to it.\n3) Give the IP address below to your friend to join.',
    },
    'joinInstructions': {
      AppLanguage.amharic: 'ከአስተናጋጁ ስልክ የሚታየውን IP አድራሻ አስገባ (ብዙ ጊዜ ከ192.168… ይጀምራል)።',
      AppLanguage.english:
          'Type the IP shown on the host phone (usually starts with 192.168…).',
    },
    'yourIp': {
      AppLanguage.amharic: 'የአስተናጋጁ IP',
      AppLanguage.english: 'Your IP',
    },
    'portLabel': {
      AppLanguage.amharic: 'Port 4545',
      AppLanguage.english: 'Port 4545',
    },
    'startHosting': {
      AppLanguage.amharic: 'አስተናጋጅ ጀምር',
      AppLanguage.english: 'Start hosting',
    },
    'waitingPeer': {
      AppLanguage.amharic: 'ተጫዋች እየጠበቅን…',
      AppLanguage.english: 'Waiting for a player…',
    },
    'connectBtn': {
      AppLanguage.amharic: 'አገናኝ',
      AppLanguage.english: 'Connect',
    },
    'connectingMsg': {
      AppLanguage.amharic: 'እያገናኘ ነው…',
      AppLanguage.english: 'Connecting…',
    },
    'connectFailed': {
      AppLanguage.amharic: 'መገናኘት አልተቻለም — IP አድራሻውን አረጋግጥ',
      AppLanguage.english: 'Connection failed — check the IP address',
    },
    'ipInvalid': {
      AppLanguage.amharic: 'ትክክለኛ IP አድራሻ አስገባ',
      AppLanguage.english: 'Enter a valid IP address',
    },
    'copy': {
      AppLanguage.amharic: 'ቅዳ',
      AppLanguage.english: 'Copy',
    },
    'copied': {
      AppLanguage.amharic: 'ተቀድቷል',
      AppLanguage.english: 'Copied',
    },
    // ---- Banter / chat ------------------------------------------------------
    'banterTitle': {
      AppLanguage.amharic: 'የሻይ ቤት ውይይት ☕',
      AppLanguage.english: 'Tea-room banter ☕',
    },
    'banter1': {
      AppLanguage.amharic: 'እጅ አይነሳም! ✋',
      AppLanguage.english: 'No cheap moves! ✋',
    },
    'banter2': {
      AppLanguage.amharic: 'ይፉታ ነዋ! 🔥',
      AppLanguage.english: "That's a huff! 🔥",
    },
    'banter3': {
      AppLanguage.amharic: 'ተበላህ! 💥',
      AppLanguage.english: 'You got eaten! 💥',
    },
    'banter4': {
      AppLanguage.amharic: 'ተረጋጋ! ☕',
      AppLanguage.english: 'Easy, easy! ☕',
    },
    // ---- Rematch ------------------------------------------------------------
    'rematchReqTitle': {
      AppLanguage.amharic: 'የእንደገና መጫወት ጥሪ',
      AppLanguage.english: 'Rematch request',
    },
    'rematchReqBody': {
      AppLanguage.amharic: 'ተቃዋሪህ እንደገና መጫወት ይፈልጋል። ትቀበላለህ?',
      AppLanguage.english: 'Your opponent wants a rematch. Accept?',
    },
    'rematchSent': {
      AppLanguage.amharic: 'የእንደገና መጫወት ጥሪ ተልኳል',
      AppLanguage.english: 'Rematch request sent',
    },
    'rematchDeclined': {
      AppLanguage.amharic: 'የእንደገና መጫወት ጥሪው አልተቀበለም',
      AppLanguage.english: 'Rematch declined',
    },
  };
}

// ----------------------------------------------------------------------------
// Board constants & helpers
// ----------------------------------------------------------------------------

const int kEmpty = 0;
const int kWPawn = 1;
const int kWKing = 2;
const int kBPawn = 3;
const int kBKing = 4;

const List<List<int>> kDiags = <List<int>>[
  <int>[-1, -1],
  <int>[-1, 1],
  <int>[1, -1],
  <int>[1, 1],
];

int rowOf(int i) => i >> 3;
int colOf(int i) => i & 7;
int square(int r, int c) => r * 8 + c;
bool inBoard(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;
bool isDarkSquare(int i) => ((rowOf(i) + colOf(i)) & 1) == 1;

bool isWhitePiece(int p) => p == kWPawn || p == kWKing;
bool isBlackPiece(int p) => p == kBPawn || p == kBKing;
bool isKingPiece(int p) => p == kWKing || p == kBKing;
bool pieceBelongsTo(bool white, int p) =>
    white ? isWhitePiece(p) : isBlackPiece(p);

// ----------------------------------------------------------------------------
// Move model
// ----------------------------------------------------------------------------

/// A fully-resolved move:
///   * [from]      — square the piece started on
///   * [steps]     — successive landing squares (length >= 1); quiet moves
///                   have exactly one step, multi-jumps have one per jump
///   * [captured]  — squares of the captured opponent pieces, in order
///   * [promotes]  — whether the moving piece ends the move as a king
class DamaMove {
  final int from;
  final List<int> steps;
  final List<int> captured;
  final bool promotes;

  DamaMove(this.from, this.steps, this.captured, this.promotes);

  int get to => steps.isEmpty ? from : steps.last;
  bool get isCapture => captured.isNotEmpty;

  bool sameAs(DamaMove o) {
    if (from != o.from || promotes != o.promotes) return false;
    if (steps.length != o.steps.length) return false;
    if (captured.length != o.captured.length) return false;
    for (int i = 0; i < steps.length; i++) {
      if (steps[i] != o.steps[i]) return false;
    }
    for (int i = 0; i < captured.length; i++) {
      if (captured[i] != o.captured[i]) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'from': from,
        'steps': steps,
        'captured': captured,
        'promotes': promotes,
      };

  factory DamaMove.fromJson(Map<String, dynamic> j) => DamaMove(
        j['from'] as int,
        (j['steps'] as List).cast<int>(),
        (j['captured'] as List).cast<int>(),
        (j['promotes'] as bool? ?? false),
      );

  @override
  String toString() =>
      'DamaMove(from: $from, to: $to, captured: ${captured.length})';
}

// ----------------------------------------------------------------------------
// Game options
// ----------------------------------------------------------------------------

class GameOptions {
  PawnCaptureMode pawnCapture;
  YifutaMode yifuta;
  Difficulty difficulty;
  bool hapticsOn;

  GameOptions({
    this.pawnCapture = PawnCaptureMode.fourWay,
    this.yifuta = YifutaMode.traditional,
    this.difficulty = Difficulty.medium,
    this.hapticsOn = true,
  });

  GameOptions copy() => GameOptions(
        pawnCapture: pawnCapture,
        yifuta: yifuta,
        difficulty: difficulty,
        hapticsOn: hapticsOn,
      );

  Map<String, dynamic> toNet() => <String, dynamic>{
        'pcm': pawnCapture.index,
        'yifuta': yifuta.index,
      };
}

// ----------------------------------------------------------------------------
// Rules engine (pure Dart, no Flutter imports needed by this section)
// ----------------------------------------------------------------------------

class DamaEngine {
  /// Fresh board: black on rows 0..2 (top), white on rows 5..7 (bottom),
  /// dark squares only.
  static List<int> initialBoard() {
    final b = List<int>.filled(64, kEmpty);
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 8; c++) {
        if (((r + c) & 1) == 1) b[square(r, c)] = kBPawn;
      }
    }
    for (int r = 5; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        if (((r + c) & 1) == 1) b[square(r, c)] = kWPawn;
      }
    }
    return b;
  }

  static List<int> cloneBoard(List<int> b) => List<int>.from(b);

  static int countPieces(List<int> b, bool white) {
    int n = 0;
    for (final p in b) {
      if (white ? isWhitePiece(p) : isBlackPiece(p)) n++;
    }
    return n;
  }

  /// Capture directions available to a pawn under the current setting.
  static List<List<int>> pawnCaptureDirs(bool white, PawnCaptureMode pcm) {
    if (pcm == PawnCaptureMode.fourWay) return kDiags;
    return white
        ? const <List<int>>[
            <int>[-1, -1],
            <int>[-1, 1],
          ]
        : const <List<int>>[
            <int>[1, -1],
            <int>[1, 1],
          ];
  }

  // ---- Move generation -----------------------------------------------------

  /// Every pseudo-legal move for [white]: quiet moves plus complete
  /// (maximal) capture sequences. In traditional Yifuta mode this is also
  /// the full legal move set — missing a capture is allowed and may be
  /// punished afterwards.
  static List<DamaMove> allMoves(List<int> b, bool white, PawnCaptureMode pcm) {
    final out = <DamaMove>[];
    for (int i = 0; i < 64; i++) {
      final p = b[i];
      if (p == kEmpty) continue;
      if (isWhitePiece(p) != white) continue;
      if (p == kWKing || p == kBKing) {
        _kingCaptureSequences(b, i, white, <int>[], <int>[], i, out);
        _kingQuietMoves(b, i, out);
      } else {
        _pawnCaptureSequences(b, i, white, pcm, <int>[], <int>[], i, out);
        _pawnQuietMoves(b, i, white, out);
      }
    }
    return out;
  }

  /// Moves filtered by the active rule mode:
  ///   * strict        — captures are mandatory when available
  ///   * forceCaptureOnly — after a "force" Yifuta decision, the locked
  ///                        player may only capture
  static List<DamaMove> legalMoves(
    List<int> b,
    bool white,
    GameOptions opt, {
    bool forceCaptureOnly = false,
  }) {
    final all = allMoves(b, white, opt.pawnCapture);
    final caps = <DamaMove>[];
    for (final m in all) {
      if (m.isCapture) caps.add(m);
    }
    if (caps.isNotEmpty) {
      if (opt.yifuta == YifutaMode.strict) return caps;
      if (forceCaptureOnly) return caps;
    }
    return all;
  }

  /// Squares of the given side's pieces that currently have at least one
  /// capture available (used by the Yifuta system).
  static List<int> capturers(List<int> b, bool white, PawnCaptureMode pcm) {
    final res = <int>[];
    for (int i = 0; i < 64; i++) {
      final p = b[i];
      if (p == kEmpty) continue;
      if (isWhitePiece(p) != white) continue;
      if (p == kWKing || p == kBKing) {
        if (_kingHasCapture(b, i, white)) res.add(i);
      } else if (_pawnHasCapture(b, i, white, pcm)) {
        res.add(i);
      }
    }
    return res;
  }

  static bool _pawnHasCapture(
      List<int> b, int from, bool white, PawnCaptureMode pcm) {
    for (final d in pawnCaptureDirs(white, pcm)) {
      final vr = rowOf(from) + d[0];
      final vc = colOf(from) + d[1];
      final lr = vr + d[0];
      final lc = vc + d[1];
      if (!inBoard(lr, lc)) continue;
      final v = b[square(vr, vc)];
      if (v == kEmpty || pieceBelongsTo(white, v)) continue;
      if (b[square(lr, lc)] == kEmpty) return true;
    }
    return false;
  }

  static bool _kingHasCapture(List<int> b, int from, bool white) {
    for (final d in kDiags) {
      int r = rowOf(from) + d[0];
      int c = colOf(from) + d[1];
      while (inBoard(r, c) && b[square(r, c)] == kEmpty) {
        r += d[0];
        c += d[1];
      }
      if (!inBoard(r, c)) continue;
      final v = b[square(r, c)];
      if (pieceBelongsTo(white, v)) continue;
      final lr = r + d[0];
      final lc = c + d[1];
      if (inBoard(lr, lc) && b[square(lr, lc)] == kEmpty) return true;
    }
    return false;
  }

  /// Pawn quiet moves: one step diagonally forward into an empty dark
  /// square. Reaching the last row promotes.
  static void _pawnQuietMoves(
      List<int> b, int from, bool white, List<DamaMove> out) {
    final fr = white ? -1 : 1;
    final promoRow = white ? 0 : 7;
    for (final dc in const <int>[-1, 1]) {
      final r = rowOf(from) + fr;
      final c = colOf(from) + dc;
      if (!inBoard(r, c)) continue;
      final s = square(r, c);
      if (b[s] != kEmpty) continue;
      out.add(DamaMove(from, <int>[s], const <int>[], r == promoRow));
    }
  }

  /// Flying-king quiet moves: slide any number of empty squares along a
  /// clear diagonal.
  static void _kingQuietMoves(List<int> b, int from, List<DamaMove> out) {
    for (final d in kDiags) {
      int r = rowOf(from) + d[0];
      int c = colOf(from) + d[1];
      while (inBoard(r, c) && b[square(r, c)] == kEmpty) {
        out.add(DamaMove(from, <int>[square(r, c)], const <int>[], false));
        r += d[0];
        c += d[1];
      }
    }
  }

  /// Recursive pawn capture generation. Victims are removed from the
  /// working board while the sequence is explored, which both prevents
  /// jumping the same piece twice (anti-loop) and mirrors the "removed
  /// cleanly" semantics of the spec. Only maximal sequences are emitted
  /// (multi-jumps must be completed). Landing on the promotion row ends
  /// the sequence immediately.
  static bool _pawnCaptureSequences(
    List<int> b,
    int from,
    bool white,
    PawnCaptureMode pcm,
    List<int> steps,
    List<int> captured,
    int root,
    List<DamaMove> out,
  ) {
    final pawn = white ? kWPawn : kBPawn;
    final promoRow = white ? 0 : 7;
    bool any = false;
    for (final d in pawnCaptureDirs(white, pcm)) {
      final vr = rowOf(from) + d[0];
      final vc = colOf(from) + d[1];
      final lr = vr + d[0];
      final lc = vc + d[1];
      if (!inBoard(lr, lc)) continue;
      final vs = square(vr, vc);
      final ls = square(lr, lc);
      final victim = b[vs];
      if (victim == kEmpty || pieceBelongsTo(white, victim)) continue;
      if (b[ls] != kEmpty) continue;

      // Apply on the working board.
      b[from] = kEmpty;
      b[vs] = kEmpty;
      b[ls] = pawn;
      steps.add(ls);
      captured.add(vs);

      final isPromo = rowOf(ls) == promoRow;
      bool extended = false;
      if (!isPromo) {
        extended = _pawnCaptureSequences(
            b, ls, white, pcm, steps, captured, root, out);
      }
      if (!extended) {
        out.add(DamaMove(
            root, List<int>.of(steps), List<int>.of(captured), isPromo));
      }

      // Undo.
      steps.removeLast();
      captured.removeLast();
      b[ls] = kEmpty;
      b[vs] = victim;
      b[from] = pawn;
      any = true;
    }
    return any;
  }

  /// Recursive flying-king capture generation. The king may jump an
  /// opponent piece at any distance along a clear diagonal and land on ANY
  /// consecutive empty square behind it; multi-jumps may continue along the
  /// same or a perpendicular diagonal from the landing square.
  static bool _kingCaptureSequences(
    List<int> b,
    int from,
    bool white,
    List<int> steps,
    List<int> captured,
    int root,
    List<DamaMove> out,
  ) {
    final king = white ? kWKing : kBKing;
    bool any = false;
    for (final d in kDiags) {
      int r = rowOf(from) + d[0];
      int c = colOf(from) + d[1];
      // Walk across the empty run-up.
      while (inBoard(r, c) && b[square(r, c)] == kEmpty) {
        r += d[0];
        c += d[1];
      }
      if (!inBoard(r, c)) continue;
      final vs = square(r, c);
      final victim = b[vs];
      if (pieceBelongsTo(white, victim)) continue;

      // Landing squares: consecutive empties behind the victim.
      final landings = <int>[];
      int lr = r + d[0];
      int lc = c + d[1];
      while (inBoard(lr, lc) && b[square(lr, lc)] == kEmpty) {
        landings.add(square(lr, lc));
        lr += d[0];
        lc += d[1];
      }
      if (landings.isEmpty) continue;

      // Apply: vacate origin, remove victim (anti-loop by clean removal).
      b[from] = kEmpty;
      b[vs] = kEmpty;
      for (final ls in landings) {
        b[ls] = king;
        steps.add(ls);
        captured.add(vs);
        final extended =
            _kingCaptureSequences(b, ls, white, steps, captured, root, out);
        if (!extended) {
          out.add(DamaMove(
              root, List<int>.of(steps), List<int>.of(captured), false));
        }
        steps.removeLast();
        captured.removeLast();
        b[ls] = kEmpty;
      }
      // Undo.
      b[vs] = victim;
      b[from] = king;
      any = true;
    }
    return any;
  }

  // ---- Make / unmake (used by the AI search) --------------------------------

  static _MakeUndo makeMove(List<int> b, DamaMove m) {
    final moved = b[m.from];
    final placed =
        m.promotes ? (isWhitePiece(moved) ? kWKing : kBKing) : moved;
    final capSq = List<int>.of(m.captured);
    final capPc = <int>[];
    for (final v in m.captured) {
      capPc.add(b[v]);
    }
    for (final v in m.captured) {
      b[v] = kEmpty;
    }
    b[m.from] = kEmpty;
    b[m.to] = placed;
    return _MakeUndo(m.from, m.to, moved, placed, capSq, capPc);
  }

  static void unmakeMove(List<int> b, DamaMove m, _MakeUndo u) {
    b[u.to] = kEmpty;
    b[u.from] = u.moved;
    for (int k = 0; k < u.capSq.length; k++) {
      b[u.capSq[k]] = u.capPc[k];
    }
  }

  /// Applies a move to a board for permanent effect (UI commit / network).
  static void applyMove(List<int> b, DamaMove m) {
    final piece = b[m.from];
    for (final v in m.captured) {
      b[v] = kEmpty;
    }
    b[m.from] = kEmpty;
    b[m.to] =
        m.promotes ? (isWhitePiece(piece) ? kWKing : kBKing) : piece;
  }

  // ---- Evaluation -----------------------------------------------------------

  /// Static evaluation from White's perspective (positive = good for
  /// White). See the heuristic weights in the spec:
  ///   material 100/350, long-diagonal +20, center 4x4 +12, home row +18,
  ///   safe advancement +4/row, mobility +5 per (pseudo) legal move.
  static int evaluate(List<int> b) {
    int score = 0;
    int wMob = 0;
    int bMob = 0;
    for (int i = 0; i < 64; i++) {
      final p = b[i];
      if (p == kEmpty) continue;
      final r = i >> 3;
      switch (p) {
        case kWPawn:
          score += 100 + _posWhite[i] + 4 * (7 - r);
          wMob += _fwdEmpty(b, i, true);
          break;
        case kWKing:
          score += 350 + _posWhite[i];
          wMob += 2 * _adjEmpty(b, i);
          break;
        case kBPawn:
          score -= 100 + _posBlack[i] + 4 * r;
          bMob += _fwdEmpty(b, i, false);
          break;
        case kBKing:
          score -= 350 + _posBlack[i];
          bMob += 2 * _adjEmpty(b, i);
          break;
        default:
          break;
      }
    }
    score += 5 * (wMob - bMob);
    return score;
  }

  /// Positional bonus table for white pieces. `row == col` squares are
  /// light squares that can never hold a piece (kept for spec fidelity),
  /// `row + col == 7` is the main playable long dark diagonal, and the two
  /// adjacent dark diagonals (|row - col| == 1) complete the long-diagonal
  /// control bonus.
  static final List<int> _posWhite = _buildBonus(true);
  static final List<int> _posBlack = _buildBonus(false);

  static List<int> _buildBonus(bool white) {
    final t = List<int>.filled(64, 0);
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        int bonus = 0;
        final onLongDiagonal =
            (r == c) || (r + c == 7) || ((r - c).abs() == 1);
        if (onLongDiagonal) bonus += 20;
        if (r >= 2 && r <= 5 && c >= 2 && c <= 5) bonus += 12;
        final homeRow = white ? 7 : 0;
        if (r == homeRow) bonus += 18;
        t[square(r, c)] = bonus;
      }
    }
    return t;
  }

  static int _fwdEmpty(List<int> b, int i, bool white) {
    int n = 0;
    final fr = white ? -1 : 1;
    final r = i >> 3;
    final c = i & 7;
    for (final dc in const <int>[-1, 1]) {
      final rr = r + fr;
      final cc = c + dc;
      if (inBoard(rr, cc) && b[square(rr, cc)] == kEmpty) n++;
    }
    return n;
  }

  static int _adjEmpty(List<int> b, int i) {
    int n = 0;
    final r = i >> 3;
    final c = i & 7;
    for (final d in kDiags) {
      final rr = r + d[0];
      final cc = c + d[1];
      if (inBoard(rr, cc) && b[square(rr, cc)] == kEmpty) n++;
    }
    return n;
  }
}

class _MakeUndo {
  final int from;
  final int to;
  final int moved;
  final int placed;
  final List<int> capSq;
  final List<int> capPc;
  _MakeUndo(this.from, this.to, this.moved, this.placed, this.capSq, this.capPc);
}

// ----------------------------------------------------------------------------
// Grandmaster AI ("የዳማ አውራ")
//
// Runs entirely inside a Dart isolate via compute(). The functions below are
// pure top-level functions so their arguments/results can cross isolate
// boundaries as plain maps/lists.
// ----------------------------------------------------------------------------

class _TimeUp implements Exception {}

class _Searcher {
  final PawnCaptureMode pcm;
  final bool capturesOnly;
  final int timeLimitMs;
  final Stopwatch _clock = Stopwatch();
  int nodes = 0;

  static const int kInf = 1000000;
  static const int kMate = 100000;

  _Searcher(this.pcm, this.capturesOnly, this.timeLimitMs);

  void start() => _clock.start();

  /// Move generation matching the active rule mode. When captures are
  /// mandatory (strict mode / forced-lock) the move set collapses to
  /// captures — but only if at least one capture exists, otherwise quiet
  /// moves remain legal.
  List<DamaMove> _gen(List<int> b, bool white) {
    final all = DamaEngine.allMoves(b, white, pcm);
    if (!capturesOnly) return all;
    final caps = <DamaMove>[];
    for (final m in all) {
      if (m.isCapture) caps.add(m);
    }
    return caps.isNotEmpty ? caps : all;
  }

  /// Negamax with alpha-beta pruning and capture-only quiescence at the
  /// horizon. Quiescence terminates because every capture removes material.
  int negamax(List<int> b, bool whiteToMove, int depth, int alpha, int beta) {
    nodes++;
    if ((nodes & 1023) == 0 && _clock.elapsedMilliseconds > timeLimitMs) {
      throw _TimeUp();
    }
    var moves = _gen(b, whiteToMove);
    if (moves.isEmpty) return -(kMate + depth); // no moves: mover loses
    if (depth <= 0) {
      bool hasCaps = false;
      for (final m in moves) {
        if (m.isCapture) {
          hasCaps = true;
          break;
        }
      }
      if (!hasCaps) {
        return whiteToMove ? DamaEngine.evaluate(b) : -DamaEngine.evaluate(b);
      }
      // Quiescence: keep searching captures only.
      final caps = <DamaMove>[];
      for (final m in moves) {
        if (m.isCapture) caps.add(m);
      }
      moves = caps;
    }
    orderMoves(moves);
    int best = -kInf;
    for (final m in moves) {
      final u = DamaEngine.makeMove(b, m);
      final v = -negamax(b, !whiteToMove, depth - 1, -beta, -alpha);
      DamaEngine.unmakeMove(b, m, u);
      if (v > best) best = v;
      if (best > alpha) alpha = best;
      if (alpha >= beta) break;
    }
    return best;
  }

  /// Move ordering to maximize alpha-beta cutoffs:
  /// (1) multi-captures, (2) single captures, (3) promotions,
  /// (4) center-control destinations.
  static void orderMoves(List<DamaMove> moves) {
    moves.sort((a, b) {
      final sa =
          a.captured.length * 1000 + (a.promotes ? 500 : 0) + _center(a.to);
      final sb =
          b.captured.length * 1000 + (b.promotes ? 500 : 0) + _center(b.to);
      return sb.compareTo(sa);
    });
  }

  static int _center(int i) {
    final r = i >> 3;
    final c = i & 7;
    if (r >= 2 && r <= 5 && c >= 2 && c <= 5) return 50;
    if (r >= 1 && r <= 6 && c >= 1 && c <= 6) return 20;
    return 0;
  }
}

/// Top-level isolate entry: computes the AI's best move.
/// Parameters (plain, sendable):
///   board       — List<int> 64
///   aiWhite     — bool (the AI side; false in Vs-AI games)
///   pcm         — int index of PawnCaptureMode
///   capturesOnly— bool (strict mode or yifuta force-lock)
///   difficulty  — int index of Difficulty
///   timeLimitMs — int
///   seed        — int RNG seed for the easy level's randomness
Map<String, dynamic> computeAiMove(Map<String, dynamic> params) {
  final board = List<int>.from(params['board'] as List);
  final aiWhite = params['aiWhite'] as bool;
  final pcm = PawnCaptureMode.values[params['pcm'] as int];
  final capturesOnly = params['capturesOnly'] as bool;
  final diff = Difficulty.values[params['difficulty'] as int];
  final timeLimitMs = params['timeLimitMs'] as int;
  final seed = params['seed'] as int;
  final rng = Random(seed);

  final totalPieces = DamaEngine.countPieces(board, true) +
      DamaEngine.countPieces(board, false);

  int maxDepth = 4;
  int noiseMargin = 0;
  if (diff == Difficulty.easy) {
    maxDepth = 2;
    noiseMargin = 90; // slight randomness for beginners
  } else if (diff == Difficulty.medium) {
    maxDepth = 4;
  } else {
    maxDepth = (totalPieces <= 8) ? 8 : 7; // deeper in endgames
  }

  final searcher = _Searcher(pcm, capturesOnly, timeLimitMs);
  searcher.start();
  final rootMoves = searcher._gen(board, aiWhite);
  if (rootMoves.isEmpty) return <String, dynamic>{'ok': false};
  _Searcher.orderMoves(rootMoves);

  DamaMove? best;
  int bestScore = 0;
  int reachedDepth = 0;

  for (int depth = 1; depth <= maxDepth; depth++) {
    try {
      if (noiseMargin > 0) {
        // Easy level: score every root move with a full window, then pick
        // randomly among all moves that are near-equal to the best one.
        final scored = <MapEntry<DamaMove, int>>[];
        for (final m in rootMoves) {
          final u = DamaEngine.makeMove(board, m);
          final v = -searcher.negamax(board, !aiWhite, depth - 1,
              -_Searcher.kInf, _Searcher.kInf);
          DamaEngine.unmakeMove(board, m, u);
          scored.add(MapEntry<DamaMove, int>(m, v));
        }
        scored.sort((a, b) => b.value.compareTo(a.value));
        final top = scored.first.value;
        final candidates = <DamaMove>[
          for (final e in scored)
            if (e.value >= top - noiseMargin) e.key
        ];
        best = candidates[rng.nextInt(candidates.length)];
        bestScore = top;
        reachedDepth = depth;
      } else {
        DamaMove? localBest;
        int localBestScore = -_Searcher.kInf - 1;
        int alpha = -_Searcher.kInf;
        const beta = _Searcher.kInf;
        for (final m in rootMoves) {
          final u = DamaEngine.makeMove(board, m);
          final v = -searcher.negamax(
              board, !aiWhite, depth - 1, -beta, -alpha);
          DamaEngine.unmakeMove(board, m, u);
          if (v > localBestScore) {
            localBestScore = v;
            localBest = m;
          }
          if (v > alpha) alpha = v;
        }
        best = localBest;
        bestScore = localBestScore;
        reachedDepth = depth;
        if (localBest != null) {
          rootMoves.remove(localBest);
          rootMoves.insert(0, localBest);
        }
        if (bestScore > _Searcher.kMate - 200) break; // forced win found
      }
    } on _TimeUp {
      break; // keep the best move from the last completed depth
    }
  }

  if (best == null) best = rootMoves.first;
  return <String, dynamic>{
    'ok': true,
    'from': best.from,
    'steps': best.steps,
    'captured': best.captured,
    'promotes': best.promotes,
    'score': bestScore,
    'depth': reachedDepth,
    'nodes': searcher.nodes,
  };
}

/// Top-level isolate entry: decides the AI's Yifuta verdict when the human
/// misses a capture in traditional mode.
///
///   Branch A (burn)   — remove the offending piece, AI moves next
///   Branch B (force)  — rewind, the human is locked into the capture
///                       (human is assumed to pick their best capture),
///                       then the AI responds
/// The AI picks whichever branch evaluates higher from its perspective.
Map<String, dynamic> computeYifutaDecision(Map<String, dynamic> params) {
  final boardBefore = List<int>.from(params['boardBefore'] as List);
  final boardAfter = List<int>.from(params['boardAfter'] as List);
  final burnSquare = params['burnSquare'] as int;
  final pcm = PawnCaptureMode.values[params['pcm'] as int];
  final misserWhite = params['humanWhite'] as bool;
  final depth = params['depth'] as int;

  final searcher = _Searcher(pcm, false, 2500);
  searcher.start();
  final aiWhite = !misserWhite;

  // Branch A: burn.
  final bA = List<int>.from(boardAfter);
  if (burnSquare >= 0 && burnSquare < 64) bA[burnSquare] = kEmpty;
  int scoreA;
  try {
    scoreA = searcher.negamax(
        bA, aiWhite, depth, -_Searcher.kInf, _Searcher.kInf);
  } on _TimeUp {
    scoreA = aiWhite ? DamaEngine.evaluate(bA) : -DamaEngine.evaluate(bA);
  }

  // Branch B: force the capture (misser picks their best capture).
  int scoreB;
  final humanCaps = <DamaMove>[];
  for (final m in DamaEngine.allMoves(boardBefore, misserWhite, pcm)) {
    if (m.isCapture) humanCaps.add(m);
  }
  if (humanCaps.isEmpty) {
    scoreB = -_Searcher.kInf - 1; // forcing impossible — burn by default
  } else {
    scoreB = _Searcher.kInf;
    for (final m in humanCaps) {
      final bB = List<int>.from(boardBefore);
      DamaEngine.applyMove(bB, m);
      int v;
      try {
        v = searcher.negamax(
            bB, aiWhite, depth, -_Searcher.kInf, _Searcher.kInf);
      } on _TimeUp {
        v = aiWhite ? DamaEngine.evaluate(bB) : -DamaEngine.evaluate(bB);
      }
      if (v < scoreB) scoreB = v;
    }
  }

  final choice = (scoreA >= scoreB) ? 'burn' : 'force';
  return <String, dynamic>{
    'choice': choice,
    'scoreA': scoreA,
    'scoreB': scoreB,
  };
}

// ----------------------------------------------------------------------------
// Persistent preferences
// ----------------------------------------------------------------------------

class AppPrefs {
  static late final SharedPreferences _prefs;

  static int _idx(int? v, int maxIdx) {
    if (v == null || v < 0 || v > maxIdx) return 0;
    return v;
  }

  static Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final langIdx = _prefs.getInt('dama.lang');
    S.lang = _idx(langIdx, 1) == 0
        ? AppLanguage.amharic
        : AppLanguage.english;
    languageNotifier.value = S.lang;
  }

  static GameOptions loadOptions() => GameOptions(
        pawnCapture:
            PawnCaptureMode.values[_idx(_prefs.getInt('dama.pcm'), 1)],
        yifuta: YifutaMode.values[_idx(_prefs.getInt('dama.yifuta'), 1)],
        difficulty:
            Difficulty.values[_idx(_prefs.getInt('dama.difficulty'), 2)],
        hapticsOn: _prefs.getBool('dama.haptics') ?? true,
      );

  static Future<void> saveOptions(GameOptions o) async {
    await _prefs.setInt('dama.pcm', o.pawnCapture.index);
    await _prefs.setInt('dama.yifuta', o.yifuta.index);
    await _prefs.setInt('dama.difficulty', o.difficulty.index);
    await _prefs.setBool('dama.haptics', o.hapticsOn);
  }

  static Future<void> saveLanguage(AppLanguage l) async {
    S.lang = l;
    languageNotifier.value = l;
    await _prefs.setInt('dama.lang', l.index);
  }
}

// ----------------------------------------------------------------------------
// Offline Wi-Fi / Hotspot TCP networking (dart:io, zero internet required)
// ----------------------------------------------------------------------------

/// Line-delimited JSON protocol over a raw TCP socket on port 4545.
/// Message types: ready, init, move, yifuta_decision, chat,
/// rematch_request, rematch_reply, resign, disconnect.
class NetLink {
  final bool isHost;
  ServerSocket? _server;
  StreamSubscription? _serverSub;
  StreamSubscription? _wireSub;
  Socket? _socket;
  String? localIp;

  final _incoming = StreamController<Map<String, dynamic>>.broadcast();
  final Completer<void> _clientConnected = Completer<void>();

  NetLink({required this.isHost});

  Stream<Map<String, dynamic>> get stream => _incoming.stream;
  Future<void> get connected => _clientConnected.future;

  /// Binds a server on 0.0.0.0:4545 and resolves the local Wi-Fi /
  /// Hotspot IP. The returned future completes immediately; await
  /// [connected] to know when a client has joined.
  Future<String> startHost() async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, 4545);
    _server = server;
    localIp = await _localIpv4();
    _serverSub = server.listen(
      (Socket client) {
        _wire(client);
        _serverSub?.cancel();
        server.close();
        _server = null;
        if (!_clientConnected.isCompleted) _clientConnected.complete();
      },
      onError: (Object e) {
        if (!_clientConnected.isCompleted) _clientConnected.completeError(e);
      },
    );
    return localIp ?? '0.0.0.0';
  }

  Future<void> connectTo(String ip) async {
    final s = await Socket.connect(ip, 4545,
        timeout: const Duration(seconds: 8));
    _wire(s);
  }

  void _wire(Socket s) {
    _socket = s;
    _wireSub = s
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (String line) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) return;
            try {
              final decoded = jsonDecode(trimmed);
              if (decoded is Map<String, dynamic> &&
                  !_incoming.isClosed) {
                _incoming.add(decoded);
              }
            } catch (_) {
              // Ignore malformed lines.
            }
          },
          onDone: () {
            if (!_incoming.isClosed) {
              _incoming.add(<String, dynamic>{'t': 'disconnect'});
            }
          },
          onError: (Object e) {
            if (!_incoming.isClosed) {
              _incoming.add(<String, dynamic>{'t': 'disconnect'});
            }
          },
        );
  }

  void send(Map<String, dynamic> msg) {
    try {
      _socket?.writeln(jsonEncode(msg));
    } catch (_) {
      // Socket already dead — the disconnect event handles the UI.
    }
  }

  void dispose() {
    try {
      _wireSub?.cancel();
    } catch (_) {}
    try {
      _socket?.destroy();
    } catch (_) {}
    try {
      _server?.close();
    } catch (_) {}
    try {
      _incoming.close();
    } catch (_) {}
  }

  static Future<String> _localIpv4() async {
    try {
      final list = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final n in list) {
        for (final a in n.addresses) {
          if (a.address.startsWith('192.168.')) return a.address;
        }
      }
      for (final n in list) {
        for (final a in n.addresses) {
          return a.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }
}

// ----------------------------------------------------------------------------
// App bootstrap
// ----------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPrefs.load();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const DamaProApp());
}

class DamaProApp extends StatelessWidget {
  const DamaProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: languageNotifier,
      builder: (context, lang, _) => MaterialApp(
        title: 'የኢትዮጵያ ዳማ Pro',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const HomeScreen(),
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFFC107),
        onPrimary: Color(0xFF121212),
        secondary: Color(0xFF26A69A),
        onSecondary: Color(0xFF121212),
        surface: Color(0xFF1E1E1E),
        onSurface: Colors.white,
        error: Color(0xFFFF5252),
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1B1B1B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFFC107),
          foregroundColor: const Color(0xFF121212),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: const Color(0xFFFFC107)),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF263238),
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Home screen
// ----------------------------------------------------------------------------

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const _DamaLogo(),
                  const SizedBox(height: 18),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      S.t('appTitle'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFFC107),
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.t('tagline'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 34),
                  _MenuCard(
                    icon: Icons.smart_toy_outlined,
                    title: S.t('vsAi'),
                    subtitle: S.t('vsAiSub'),
                    onTap: () => _pickDifficultyAndStart(context),
                  ),
                  const SizedBox(height: 14),
                  _MenuCard(
                    icon: Icons.people_alt_outlined,
                    title: S.t('passPlay'),
                    subtitle: S.t('passPlaySub'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GameScreen(
                          mode: GameMode.passPlay,
                          options: AppPrefs.loadOptions(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _MenuCard(
                    icon: Icons.wifi_tethering,
                    title: S.t('hotspot'),
                    subtitle: S.t('hotspotSub'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HotspotSetupScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _MenuCard(
                    icon: Icons.tune,
                    title: S.t('settings'),
                    subtitle: S.t('settingsSub'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final next = S.isAm
                            ? AppLanguage.english
                            : AppLanguage.amharic;
                        AppPrefs.saveLanguage(next);
                      },
                      icon: const Icon(Icons.translate,
                          color: Color(0xFF26A69A)),
                      label: Text(
                        S.isAm ? 'English' : 'አማርኛ',
                        style: const TextStyle(
                            color: Color(0xFF26A69A),
                            fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF26A69A)),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      S.t('version'),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDifficultyAndStart(BuildContext context) async {
    final opt = AppPrefs.loadOptions();
    final choice = await showModalBottomSheet<Difficulty>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.t('chooseDifficulty'),
                  style: const TextStyle(
                    color: Color(0xFFFFC107),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                for (final d in Difficulty.values)
                  _DifficultyTile(
                    difficulty: d,
                    selected: opt.difficulty == d,
                    onTap: () => Navigator.of(sheetCtx).pop(d),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null) return;
    if (!context.mounted) return;
    opt.difficulty = choice;
    AppPrefs.saveOptions(opt);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameScreen(mode: GameMode.vsAi, options: opt),
      ),
    );
  }
}

class _DifficultyTile extends StatelessWidget {
  final Difficulty difficulty;
  final bool selected;
  final VoidCallback onTap;

  const _DifficultyTile({
    required this.difficulty,
    required this.selected,
    required this.onTap,
  });

  String get _title {
    switch (difficulty) {
      case Difficulty.easy:
        return S.t('easy');
      case Difficulty.medium:
        return S.t('medium');
      case Difficulty.grandmaster:
        return S.t('grandmaster');
    }
  }

  String get _subtitle {
    switch (difficulty) {
      case Difficulty.easy:
        return S.t('easySub');
      case Difficulty.medium:
        return S.t('mediumSub');
      case Difficulty.grandmaster:
        return S.t('grandmasterSub');
    }
  }

  IconData get _icon {
    switch (difficulty) {
      case Difficulty.easy:
        return Icons.sentiment_satisfied;
      case Difficulty.medium:
        return Icons.psychology;
      case Difficulty.grandmaster:
        return Icons.workspace_premium;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFF2A231A) : const Color(0xFF242424),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(_icon,
                    color: const Color(0xFFFFC107), size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E1E1E),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFFFC107), size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.35)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DamaLogo extends StatelessWidget {
  const _DamaLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _logoPiece(true),
          Transform.translate(
            offset: const Offset(0, -10),
            child: _logoPiece(false, king: true),
          ),
          _logoPiece(true),
          Transform.translate(
            offset: const Offset(0, 10),
            child: _logoPiece(false),
          ),
          _logoPiece(true, king: true),
        ],
      ),
    );
  }

  Widget _logoPiece(bool white, {bool king = false}) {
    return Container(
      width: 34,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.35),
          radius: 1.05,
          colors: white
              ? const [
                  Color(0xFFFFFFFF),
                  Color(0xFFCFD8DC),
                  Color(0xFF8D9AA3),
                ]
              : const [
                  Color(0xFF7E7E7E),
                  Color(0xFF3E3E3E),
                  Color(0xFF151515),
                ],
        ),
        boxShadow: const [
          BoxShadow(
              color: Colors.black54, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: king
          ? const Padding(
              padding: EdgeInsets.all(5),
              child: AspectRatio(
                  aspectRatio: 1.5, child: CustomPaint(painter: _CrownPainter())),
            )
          : null,
    );
  }
}

// ----------------------------------------------------------------------------
// Settings screen
// ----------------------------------------------------------------------------

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late GameOptions opt;

  @override
  void initState() {
    super.initState();
    opt = AppPrefs.loadOptions();
  }

  void _changed() {
    setState(() {});
    AppPrefs.saveOptions(opt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _sectionTitle(S.t('language')),
          RadioListTile<AppLanguage>(
            value: AppLanguage.amharic,
            groupValue: S.lang,
            activeColor: const Color(0xFFFFC107),
            title: Text(S.t('amharic')),
            onChanged: (v) {
              if (v != null) {
                AppPrefs.saveLanguage(v);
                setState(() {});
              }
            },
          ),
          RadioListTile<AppLanguage>(
            value: AppLanguage.english,
            groupValue: S.lang,
            activeColor: const Color(0xFFFFC107),
            title: Text(S.t('english')),
            onChanged: (v) {
              if (v != null) {
                AppPrefs.saveLanguage(v);
                setState(() {});
              }
            },
          ),
          const Divider(color: Color(0xFF333333)),
          _sectionTitle(S.t('difficulty')),
          for (final d in Difficulty.values)
            RadioListTile<Difficulty>(
              value: d,
              groupValue: opt.difficulty,
              activeColor: const Color(0xFFFFC107),
              title: Text(_difficultyName(d)),
              subtitle: Text(_difficultySub(d)),
              onChanged: (v) {
                if (v != null) {
                  opt.difficulty = v;
                  _changed();
                }
              },
            ),
          const Divider(color: Color(0xFF333333)),
          _sectionTitle(S.t('yifutaMode')),
          RadioListTile<YifutaMode>(
            value: YifutaMode.traditional,
            groupValue: opt.yifuta,
            activeColor: const Color(0xFFFFC107),
            title: Text(S.t('yifutaTraditional')),
            subtitle: Text(S.t('yifutaTraditionalSub')),
            onChanged: (v) {
              if (v != null) {
                opt.yifuta = v;
                _changed();
              }
            },
          ),
          RadioListTile<YifutaMode>(
            value: YifutaMode.strict,
            groupValue: opt.yifuta,
            activeColor: const Color(0xFFFFC107),
            title: Text(S.t('yifutaStrict')),
            subtitle: Text(S.t('yifutaStrictSub')),
            onChanged: (v) {
              if (v != null) {
                opt.yifuta = v;
                _changed();
              }
            },
          ),
          const Divider(color: Color(0xFF333333)),
          _sectionTitle(S.t('pawnCaptureDir')),
          RadioListTile<PawnCaptureMode>(
            value: PawnCaptureMode.fourWay,
            groupValue: opt.pawnCapture,
            activeColor: const Color(0xFFFFC107),
            title: Text(S.t('fourWay')),
            subtitle: Text(S.t('fourWaySub')),
            onChanged: (v) {
              if (v != null) {
                opt.pawnCapture = v;
                _changed();
              }
            },
          ),
          RadioListTile<PawnCaptureMode>(
            value: PawnCaptureMode.forwardOnly,
            groupValue: opt.pawnCapture,
            activeColor: const Color(0xFFFFC107),
            title: Text(S.t('forwardOnly')),
            subtitle: Text(S.t('forwardOnlySub')),
            onChanged: (v) {
              if (v != null) {
                opt.pawnCapture = v;
                _changed();
              }
            },
          ),
          const Divider(color: Color(0xFF333333)),
          _sectionTitle(S.t('haptics')),
          SwitchListTile(
            value: opt.hapticsOn,
            activeColor: const Color(0xFFFFC107),
            title: Text(S.t('haptics')),
            subtitle: Text(S.t('hapticsSub')),
            onChanged: (v) {
              opt.hapticsOn = v;
              _changed();
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: const Color(0xFFFFC107).withValues(alpha: 0.85),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      );

  String _difficultyName(Difficulty d) {
    switch (d) {
      case Difficulty.easy:
        return S.t('easy');
      case Difficulty.medium:
        return S.t('medium');
      case Difficulty.grandmaster:
        return S.t('grandmaster');
    }
  }

  String _difficultySub(Difficulty d) {
    switch (d) {
      case Difficulty.easy:
        return S.t('easySub');
      case Difficulty.medium:
        return S.t('mediumSub');
      case Difficulty.grandmaster:
        return S.t('grandmasterSub');
    }
  }
}

// ----------------------------------------------------------------------------
// Hotspot lobby (host / join)
// ----------------------------------------------------------------------------

class HotspotSetupScreen extends StatefulWidget {
  const HotspotSetupScreen({super.key});

  @override
  State<HotspotSetupScreen> createState() => _HotspotSetupScreenState();
}

class _HotspotSetupScreenState extends State<HotspotSetupScreen> {
  bool _showHost = true;
  bool _busy = false;
  bool _handedOff = false;
  String? _hostIp;
  String? _error;
  NetLink? _link;
  final TextEditingController _ipController = TextEditingController();

  @override
  void dispose() {
    _ipController.dispose();
    if (_link != null && !_handedOff) {
      _link!.dispose();
    }
    super.dispose();
  }

  Future<void> _startHosting() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final link = NetLink(isHost: true);
    _link = link;
    try {
      final ip = await link.startHost();
      if (!mounted) return;
      setState(() => _hostIp = ip);
      await link.connected;
      if (!mounted) return;
      _gotoGame(link);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = S.t('connectFailed');
      });
    }
  }

  Future<void> _join() async {
    if (_busy) return;
    final ip = _ipController.text.trim();
    final valid = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(ip);
    if (!valid) {
      setState(() => _error = S.t('ipInvalid'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final link = NetLink(isHost: false);
    _link = link;
    try {
      await link.connectTo(ip);
      if (!mounted) return;
      _gotoGame(link);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = S.t('connectFailed');
      });
    }
  }

  void _gotoGame(NetLink link) {
    _handedOff = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          mode: GameMode.hotspot,
          options: AppPrefs.loadOptions(),
          net: link,
          playerIsWhite: link.isHost,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('hotspot'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                Expanded(
                  child: _roleTab(
                    selected: _showHost,
                    icon: Icons.wifi_tethering,
                    label: S.t('host'),
                    onTap: () => setState(() {
                      _showHost = true;
                      _error = null;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _roleTab(
                    selected: !_showHost,
                    icon: Icons.phonelink_setup,
                    label: S.t('join'),
                    onTap: () => setState(() {
                      _showHost = false;
                      _error = null;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (_showHost) _buildHostPanel(),
            if (!_showHost) _buildJoinPanel(),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFFF5252)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _roleTab({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0xFF332A18) : const Color(0xFF1E1E1E),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: selected
                      ? const Color(0xFFFFC107)
                      : Colors.white54),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHostPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          S.t('hostTitle'),
          style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          S.t('hostInstructions'),
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65), fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 20),
        if (_busy && _hostIp == null)
          const Center(child: CircularProgressIndicator(color: Color(0xFFFFC107)))
        else if (_hostIp != null) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFC107), width: 1.5),
            ),
            child: Column(
              children: [
                Text(
                  S.t('yourIp'),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  _hostIp!,
                  style: const TextStyle(
                    color: Color(0xFFFFC107),
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  S.t('portLabel'),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: _hostIp ?? ''));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(S.t('copied'))),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(S.t('copy')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Color(0xFFFFC107)),
              ),
              const SizedBox(width: 12),
              Text(
                S.t('waitingPeer'),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ] else ...[
          ElevatedButton.icon(
            onPressed: _startHosting,
            icon: const Icon(Icons.wifi_tethering),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(S.t('startHosting')),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildJoinPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          S.t('joinTitle'),
          style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          S.t('joinInstructions'),
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65), fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _ipController,
          keyboardType: TextInputType.text,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: const TextStyle(
              color: Colors.white, fontSize: 22, letterSpacing: 1.5),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF1E1E1E),
            hintText: '192.168.43.1',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            prefixIcon: const Icon(Icons.lan, color: Color(0xFFFFC107)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF3E2723)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFFFC107), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: _busy ? null : _join,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Color(0xFF121212)),
                )
              : const Icon(Icons.login),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_busy ? S.t('connectingMsg') : S.t('connectBtn')),
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Game screen — widget + state controller
// ----------------------------------------------------------------------------

class GameScreen extends StatefulWidget {
  final GameMode mode;
  final GameOptions options;
  final NetLink? net;
  final bool playerIsWhite;

  const GameScreen({
    super.key,
    required this.mode,
    required this.options,
    this.net,
    this.playerIsWhite = true,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _Snapshot {
  final List<int> board;
  final bool whiteToMove;
  final int capturedByWhite;
  final int capturedByBlack;
  final int quietPlies;
  final bool forceLock;
  final List<int> forcedCapturers;
  final DamaMove? lastMove;

  _Snapshot(
    this.board,
    this.whiteToMove,
    this.capturedByWhite,
    this.capturedByBlack,
    this.quietPlies,
    this.forceLock,
    this.forcedCapturers,
    this.lastMove,
  );
}

class _StepOption {
  final int to;
  final bool isCapture;
  final int? victim;
  final bool promotes;

  _StepOption(this.to, this.isCapture, this.victim, this.promotes);
}

class _Pending {
  final int from;
  final List<int> steps;
  final List<int> captured;
  _Pending(this.from, this.steps, this.captured);
}

class _YifutaContext {
  final List<int> preBoard;
  final DamaMove quietMove;
  final int offender;
  final bool moverWhite;

  _YifutaContext({
    required this.preBoard,
    required this.quietMove,
    required this.offender,
    required this.moverWhite,
  });
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late GameOptions opt;
  late List<int> board;
  bool whiteToMove = true;
  int capturedByWhite = 0; // black pieces eaten by white
  int capturedByBlack = 0; // white pieces eaten by black
  final List<_Snapshot> _history = [];
  int _quietPlies = 0;

  bool _forceLock = false;
  List<int> _forcedCapturers = const <int>[];

  int? _selected;
  List<_StepOption> _steps = const <_StepOption>[];
  _Pending? _pending;
  DamaMove? _lastMove;

  bool _aiThinking = false;
  int _aiToken = 0;
  bool _yifutaAwaitRemote = false;
  _YifutaContext? _yifCtx;
  bool _gameOver = false;
  bool _gameOverShown = false;
  String? _overTitle;
  String? _overSub;
  bool _netDead = false;
  bool _netHandshakeDone = true;
  bool _flipped = false;

  StreamSubscription? _netSub;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
    lowerBound: 0,
    upperBound: 1,
  )..repeat(reverse: true);

  bool get _isHotspot => widget.mode == GameMode.hotspot;
  bool get _iAmWhite => widget.playerIsWhite;
  bool get _isAiTurn => widget.mode == GameMode.vsAi && !whiteToMove;

  bool _isMyTurn() {
    if (_gameOver) return false;
    if (_isHotspot) return whiteToMove == _iAmWhite;
    if (widget.mode == GameMode.vsAi) return whiteToMove;
    return true; // pass & play: both sides local
  }

  @override
  void initState() {
    super.initState();
    opt = widget.options.copy();
    board = DamaEngine.initialBoard();
    _pushSnapshot();
    if (_isHotspot) {
      final net = widget.net;
      if (net != null) {
        _netSub = net.stream.listen(_onNetMsg, onError: (Object e) {});
        if (net.isHost) {
          _netHandshakeDone = true; // host's own settings rule the game
        } else {
          _netHandshakeDone = false;
          _flipped = true; // joiner plays black from the bottom view
          net.send(<String, dynamic>{'t': 'ready'});
        }
      }
    }
  }

  @override
  void dispose() {
    _aiToken++;
    _netSub?.cancel();
    widget.net?.dispose();
    _pulse.dispose();
    super.dispose();
  }

  // ---- Small helpers --------------------------------------------------------

  void _haptic({bool heavy = false}) {
    if (opt.hapticsOn) {
      if (heavy) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  void _banner(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 4)),
    );
  }

  String _moverLabel(bool white) {
    if (widget.mode == GameMode.vsAi) {
      return white ? S.t('you') : S.t('ai');
    }
    if (_isHotspot) {
      return white == _iAmWhite ? S.t('you') : S.t('opponent');
    }
    return white ? S.t('white') : S.t('black');
  }

  String _winnerTitle(bool whiteWon) {
    if (widget.mode == GameMode.vsAi) {
      return whiteWon ? S.t('youWin') : S.t('youLose');
    }
    if (_isHotspot) {
      return whiteWon == _iAmWhite ? S.t('youWin') : S.t('youLose');
    }
    return whiteWon ? S.t('whiteWins') : S.t('blackWins');
  }

  // ---- Snapshots / undo -----------------------------------------------------

  void _pushSnapshot() {
    _history.add(_Snapshot(
      List<int>.from(board),
      whiteToMove,
      capturedByWhite,
      capturedByBlack,
      _quietPlies,
      _forceLock,
      List<int>.of(_forcedCapturers),
      _lastMove,
    ));
  }

  void _restoreSnapshot(_Snapshot s) {
    board = List<int>.from(s.board);
    whiteToMove = s.whiteToMove;
    capturedByWhite = s.capturedByWhite;
    capturedByBlack = s.capturedByBlack;
    _quietPlies = s.quietPlies;
    _forceLock = s.forceLock;
    _forcedCapturers = s.forcedCapturers;
    _lastMove = s.lastMove;
    _selected = null;
    _steps = const <_StepOption>[];
    _pending = null;
    _yifCtx = null;
    _yifutaAwaitRemote = false;
    _gameOver = false;
    _gameOverShown = false;
    _overTitle = null;
    _overSub = null;
    _aiThinking = false;
    _aiToken++;
    setState(() {});
  }

  void _undo() {
    if (_isHotspot) {
      _toast(S.t('undoNetDisabled'));
      return;
    }
    if (_aiThinking) {
      _aiToken++;
      _aiThinking = false;
    }
    // Cancel an in-progress multi-jump: revert to this turn's start.
    if (_pending != null && _history.isNotEmpty) {
      _restoreSnapshot(_history.last);
      return;
    }
    if (_history.length <= 1) {
      _toast(S.t('nothingToUndo'));
      return;
    }
    _history.removeLast(); // current turn start == current state
    if (_history.isEmpty) return;
    var s = _history.removeLast();
    if (widget.mode == GameMode.vsAi) {
      // Revert both the AI reply and the human's last move.
      while (!s.whiteToMove && _history.isNotEmpty) {
        s = _history.removeLast();
      }
    }
    _restoreSnapshot(s);
  }

  // ---- Turn pipeline --------------------------------------------------------

  void _finishTurnCommon() {
    _selected = null;
    _steps = const <_StepOption>[];
    _pending = null;
    _forceLock = false;
    _forcedCapturers = const <int>[];
    whiteToMove = !whiteToMove;
    _pushSnapshot();
    _checkGameOver();
    if (!_gameOver && _isAiTurn) _scheduleAiMove();
    setState(() {});
  }

  bool _checkGameOver() {
    if (_gameOver) return true;
    final wCount = DamaEngine.countPieces(board, true);
    final bCount = DamaEngine.countPieces(board, false);
    if (wCount == 0) {
      _endGame(_winnerTitle(false), S.t('wipeSub'));
      return true;
    }
    if (bCount == 0) {
      _endGame(_winnerTitle(true), S.t('wipeSub'));
      return true;
    }
    final moves = DamaEngine.legalMoves(board, whiteToMove, opt,
        forceCaptureOnly: _forceLock);
    if (moves.isEmpty) {
      _endGame(_winnerTitle(!whiteToMove), S.t('blockSub'));
      return true;
    }
    if (_quietPlies >= 60) {
      _endGame(S.t('draw'), S.t('drawSub'));
      return true;
    }
    return false;
  }

  void _endGame(String title, String sub) {
    _gameOver = true;
    _overTitle = title;
    _overSub = sub;
    _aiThinking = false;
    _aiToken++;
    _selected = null;
    _steps = const <_StepOption>[];
    _pending = null;
    _haptic(heavy: true);
    setState(() {});
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && !_gameOverShown) {
        _gameOverShown = true;
        _showGameOverDialog();
      }
    });
  }

  // ---- Selection & step computation ------------------------------------------

  void _onTapSquare(int sq) {
    if (_gameOver || _netDead) return;
    if (_yifCtx != null || _yifutaAwaitRemote || _aiThinking) return;
    if (_isHotspot && !_netHandshakeDone) return;
    if (!_isMyTurn()) return;

    final matches = <_StepOption>[
      for (final s in _steps)
        if (s.to == sq) s
    ];
    if (matches.isNotEmpty) {
      _executeStep(matches.first);
      return;
    }

    final p = board[sq];
    if (p != kEmpty && isWhitePiece(p) == whiteToMove) {
      if (_pending != null) return; // mid multi-jump: locked to this piece
      if (_forceLock && !_forcedCapturers.contains(sq)) {
        _toast(S.t('mustCaptureHint'));
        return;
      }
      _select(sq);
      return;
    }
    if (_pending == null && _selected != null) {
      _selected = null;
      _steps = const <_StepOption>[];
      setState(() {});
    }
  }

  void _select(int sq) {
    final capturesOnly =
        _forceLock || _pending != null || opt.yifuta == YifutaMode.strict;
    var steps = _computeStepsFor(sq, capturesOnly: capturesOnly);
    if (steps.isEmpty && capturesOnly) {
      // No captures available at all — quiet moves stay legal.
      steps = _computeStepsFor(sq);
    }
    _selected = sq;
    _steps = steps;
    _haptic();
    setState(() {});
  }

  /// One-tap destinations for the piece on [sq] in the current board state.
  /// Each capture option is uniquely determined by its landing square
  /// (the victim is the first piece on that ray), so tap-to-move is
  /// unambiguous for pawns and flying kings alike.
  List<_StepOption> _computeStepsFor(int sq, {bool capturesOnly = false}) {
    final res = <_StepOption>[];
    final p = board[sq];
    if (p == kEmpty) return res;
    final white = isWhitePiece(p);

    if (p == kWKing || p == kBKing) {
      // Flying-king captures.
      for (final d in kDiags) {
        int r = rowOf(sq) + d[0];
        int c = colOf(sq) + d[1];
        while (inBoard(r, c) && board[square(r, c)] == kEmpty) {
          r += d[0];
          c += d[1];
        }
        if (!inBoard(r, c)) continue;
        final vs = square(r, c);
        final victim = board[vs];
        if (pieceBelongsTo(white, victim)) continue;
        int lr = r + d[0];
        int lc = c + d[1];
        while (inBoard(lr, lc) && board[square(lr, lc)] == kEmpty) {
          res.add(_StepOption(square(lr, lc), true, vs, false));
          lr += d[0];
          lc += d[1];
        }
      }
      if (!capturesOnly) {
        for (final d in kDiags) {
          int r = rowOf(sq) + d[0];
          int c = colOf(sq) + d[1];
          while (inBoard(r, c) && board[square(r, c)] == kEmpty) {
            res.add(_StepOption(square(r, c), false, null, false));
            r += d[0];
            c += d[1];
          }
        }
      }
    } else {
      // Pawn captures (forward+backward in 4-way mode).
      for (final d in DamaEngine.pawnCaptureDirs(white, opt.pawnCapture)) {
        final vr = rowOf(sq) + d[0];
        final vc = colOf(sq) + d[1];
        final lr = vr + d[0];
        final lc = vc + d[1];
        if (!inBoard(lr, lc)) continue;
        final vs = square(vr, vc);
        final victim = board[vs];
        if (victim == kEmpty || pieceBelongsTo(white, victim)) continue;
        if (board[square(lr, lc)] != kEmpty) continue;
        final promo = lr == (white ? 0 : 7);
        res.add(_StepOption(square(lr, lc), true, vs, promo));
      }
      if (!capturesOnly) {
        final fr = white ? -1 : 1;
        for (final dc in const <int>[-1, 1]) {
          final r = rowOf(sq) + fr;
          final c = colOf(sq) + dc;
          if (!inBoard(r, c)) continue;
          final s = square(r, c);
          if (board[s] != kEmpty) continue;
          res.add(_StepOption(s, false, null, r == (white ? 0 : 7)));
        }
      }
    }
    return res;
  }

  // ---- Executing a step ------------------------------------------------------

  void _executeStep(_StepOption step) {
    final from = _selected;
    if (from == null) return;

    if (!step.isCapture) {
      _attemptQuietMove(from, step.to, step.promotes);
      return;
    }

    _haptic(heavy: true);
    final piece = board[from];
    board[from] = kEmpty;
    board[step.victim!] = kEmpty;
    board[step.to] = piece;

    if (_pending == null) {
      _pending = _Pending(from, <int>[step.to], <int>[step.victim!]);
    } else {
      _pending!.steps.add(step.to);
      _pending!.captured.add(step.victim!);
    }

    if (step.promotes) {
      // Promotion during a capture ends the turn immediately.
      board[step.to] = isWhitePiece(piece) ? kWKing : kBKing;
      final m = DamaMove(
        _pending!.from,
        List<int>.of(_pending!.steps),
        List<int>.of(_pending!.captured),
        true,
      );
      _toast(S.t('promotedToast'));
      _commitCaptureMove(m);
      return;
    }

    // Mandatory multi-jump continuation.
    final next = _computeStepsFor(step.to, capturesOnly: true);
    if (next.isEmpty) {
      final m = DamaMove(
        _pending!.from,
        List<int>.of(_pending!.steps),
        List<int>.of(_pending!.captured),
        false,
      );
      _commitCaptureMove(m);
    } else {
      _selected = step.to;
      _steps = next;
      setState(() {});
    }
  }

  void _commitCaptureMove(DamaMove m) {
    _pending = null;
    _selected = null;
    _steps = const <_StepOption>[];
    _lastMove = m;
    if (m.captured.isNotEmpty) {
      if (isWhitePiece(board[m.to])) {
        capturedByWhite += m.captured.length;
      } else {
        capturedByBlack += m.captured.length;
      }
    }
    _quietPlies = 0;
    _haptic(heavy: true);
    if (_isHotspot && _isMyTurn()) {
      widget.net?.send(<String, dynamic>{'t': 'move', ...m.toJson()});
    }
    _finishTurnCommon();
  }

  void _attemptQuietMove(int from, int to, bool promotes) {
    final m = DamaMove(from, <int>[to], const <int>[], promotes);
    final preBoard = List<int>.from(board);
    DamaEngine.applyMove(board, m);
    _lastMove = m;
    _selected = null;
    _steps = const <_StepOption>[];
    _handleQuietDone(m, preBoard, whiteToMove, moveOriginLocal: true);
  }

  /// Shared quiet-move completion: either the move stands and the turn
  /// passes, or (traditional Yifuta + a capture was available) the
  /// opponent gets the Yifuta decision.
  void _handleQuietDone(
    DamaMove m,
    List<int> preBoard,
    bool moverWhite, {
    required bool moveOriginLocal,
  }) {
    final caps = DamaEngine.capturers(preBoard, moverWhite, opt.pawnCapture);
    if (caps.isNotEmpty && opt.yifuta == YifutaMode.traditional) {
      // ---- Yifuta trigger ----
      final offender = caps.contains(m.from) ? m.to : caps.first;
      _yifCtx = _YifutaContext(
        preBoard: preBoard,
        quietMove: m,
        offender: offender,
        moverWhite: moverWhite,
      );
      _selected = null;
      _steps = const <_StepOption>[];
      _pending = null;
      _haptic(heavy: true);
      if (_isHotspot) {
        if (moveOriginLocal) {
          widget.net
              ?.send(<String, dynamic>{'t': 'move', ...m.toJson()});
          _yifutaAwaitRemote = true;
          setState(() {});
        } else {
          _showYifutaModal();
        }
      } else if (widget.mode == GameMode.vsAi) {
        if (moverWhite) {
          _aiDecideYifuta(); // human missed — the AI punishes
        } else {
          _showYifutaModal(); // AI missed (a deliberate bait?) — human decides
        }
      } else {
        _showYifutaModal(); // pass & play
      }
    } else {
      if (m.promotes) {
        _quietPlies = 0;
        _toast(S.t('promotedToast'));
      } else {
        _quietPlies += 1;
      }
      _haptic();
      if (moveOriginLocal && _isHotspot) {
        widget.net?.send(<String, dynamic>{'t': 'move', ...m.toJson()});
      }
      _finishTurnCommon();
    }
    setState(() {});
  }

  // ---- Yifuta flow -----------------------------------------------------------

  Future<void> _showYifutaModal() async {
    final ctx = _yifCtx;
    if (ctx == null) return;
    final moverName = _moverLabel(ctx.moverWhite);
    final prompt = S.t('yifutaPrompt').replaceAll('{p}', moverName);
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ይፉታ! 🔥',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFFF5252),
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    prompt,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _yifutaButton(
                    context: dialogCtx,
                    action: 'burn',
                    color: const Color(0xFFD32F2F),
                    title: S.t('yifutaBurn'),
                    subtitle: S.t('yifutaBurnSub'),
                    icon: Icons.local_fire_department,
                  ),
                  const SizedBox(height: 10),
                  _yifutaButton(
                    context: dialogCtx,
                    action: 'force',
                    color: const Color(0xFFFF8F00),
                    title: S.t('yifutaForce'),
                    subtitle: S.t('yifutaForceSub'),
                    icon: Icons.replay,
                  ),
                  const SizedBox(height: 10),
                  _yifutaButton(
                    context: dialogCtx,
                    action: 'ignore',
                    color: const Color(0xFF37474F),
                    title: S.t('yifutaIgnore'),
                    subtitle: S.t('yifutaIgnoreSub'),
                    icon: Icons.skip_next,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (action == null) return;
    if (_yifCtx == null) return;
    if (_isHotspot) {
      widget.net
          ?.send(<String, dynamic>{'t': 'yifuta_decision', 'action': action});
    }
    _applyYifutaDecision(action);
  }

  Widget _yifutaButton({
    required BuildContext context,
    required String action,
    required Color color,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => Navigator.of(context).pop(action),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _aiDecideYifuta() async {
    final ctx = _yifCtx;
    if (ctx == null) return;
    _aiThinking = true;
    final token = ++_aiToken;
    setState(() {});
    try {
      final res = await compute(computeYifutaDecision, <String, dynamic>{
        'boardBefore': ctx.preBoard,
        'boardAfter': List<int>.from(board),
        'burnSquare': ctx.offender,
        'pcm': opt.pawnCapture.index,
        'humanWhite': ctx.moverWhite,
        'depth': 4,
      });
      if (!mounted || token != _aiToken) return;
      _aiThinking = false;
      if (_yifCtx == null) {
        setState(() {});
        return;
      }
      final action = (res['choice'] as String) == 'burn' ? 'burn' : 'force';
      _banner(action == 'burn' ? S.t('aiBurned') : S.t('aiForced'));
      _applyYifutaDecision(action);
    } catch (e) {
      if (!mounted || token != _aiToken) return;
      _aiThinking = false;
      _applyYifutaDecision('ignore');
    }
  }

  void _applyYifutaDecision(String action) {
    final ctx = _yifCtx;
    if (ctx == null || _gameOver) return;
    _yifCtx = null;
    _yifutaAwaitRemote = false;

    if (action == 'burn') {
      if (ctx.offender >= 0 && ctx.offender < 64) {
        board[ctx.offender] = kEmpty;
        if (ctx.moverWhite) {
          capturedByBlack += 1; // decider (black side) gets the credit
        } else {
          capturedByWhite += 1;
        }
      }
      _lastMove = ctx.quietMove;
      _quietPlies += 1;
      _haptic(heavy: true);
      _finishTurnCommon();
    } else if (action == 'force') {
      // Revert to the exact pre-move state and lock the mover into the
      // capture; the glowing red highlights mark the forced pieces.
      board = List<int>.from(ctx.preBoard);
      _forceLock = true;
      _forcedCapturers =
          DamaEngine.capturers(board, ctx.moverWhite, opt.pawnCapture);
      _selected = null;
      _steps = const <_StepOption>[];
      _pending = null;
      _lastMove = null;
      _haptic(heavy: true);
      setState(() {});
      if (_isAiTurn) _scheduleAiMove(); // AI was the one who missed
    } else {
      // ignore — the quiet move stands
      _lastMove = ctx.quietMove;
      _quietPlies += 1;
      _haptic();
      _finishTurnCommon();
    }
  }

  // ---- AI turns ---------------------------------------------------------------

  void _scheduleAiMove() {
    if (_gameOver || _netDead) return;
    if (widget.mode != GameMode.vsAi || whiteToMove) return;
    _aiThinking = true;
    final token = ++_aiToken;
    setState(() {});
    Future(() async {
      int timeLimitMs = 2200;
      if (opt.difficulty == Difficulty.easy) timeLimitMs = 700;
      if (opt.difficulty == Difficulty.grandmaster) timeLimitMs = 5000;
      try {
        final res = await compute(computeAiMove, <String, dynamic>{
          'board': List<int>.from(board),
          'aiWhite': false,
          'pcm': opt.pawnCapture.index,
          'capturesOnly':
              opt.yifuta == YifutaMode.strict || _forceLock,
          'difficulty': opt.difficulty.index,
          'timeLimitMs': timeLimitMs,
          'seed': DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
        });
        if (!mounted || token != _aiToken) return;
        _aiThinking = false;
        if (res['ok'] != true) {
          _checkGameOver();
          setState(() {});
          return;
        }
        final m = DamaMove(
          res['from'] as int,
          (res['steps'] as List).cast<int>(),
          (res['captured'] as List).cast<int>(),
          res['promotes'] as bool,
        );
        final legal =
            DamaEngine.legalMoves(board, false, opt, forceCaptureOnly: _forceLock);
        if (!legal.any((lm) => lm.sameAs(m))) {
          _finishTurnCommon();
          return;
        }
        if (m.isCapture) {
          DamaEngine.applyMove(board, m);
          _lastMove = m;
          capturedByBlack += m.captured.length;
          _quietPlies = 0;
          _haptic(heavy: true);
          if (m.promotes) _toast(S.t('promotedToast'));
          _finishTurnCommon();
        } else {
          final preBoard = List<int>.from(board);
          DamaEngine.applyMove(board, m);
          _lastMove = m;
          _handleQuietDone(m, preBoard, false, moveOriginLocal: false);
        }
      } catch (e) {
        if (!mounted || token != _aiToken) return;
        _aiThinking = false;
        _checkGameOver();
        setState(() {});
      }
    });
  }

  // ---- Game reset / resign -----------------------------------------------------

  void _resetBoard() {
    board = DamaEngine.initialBoard();
    whiteToMove = true;
    capturedByWhite = 0;
    capturedByBlack = 0;
    _quietPlies = 0;
    _forceLock = false;
    _forcedCapturers = const <int>[];
    _selected = null;
    _steps = const <_StepOption>[];
    _pending = null;
    _lastMove = null;
    _yifCtx = null;
    _yifutaAwaitRemote = false;
    _gameOver = false;
    _gameOverShown = false;
    _overTitle = null;
    _overSub = null;
    _netDead = false;
    _aiThinking = false;
    _aiToken++;
    _history.clear();
    _pushSnapshot();
    setState(() {});
  }

  void _confirmNewGame() {
    if (_isHotspot) {
      _requestRematch();
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(S.t('newGame')),
        content: Text(S.t('confirmNewGame')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(S.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              _resetBoard();
              _toast(S.t('gameStarted'));
            },
            child: Text(S.t('confirm')),
          ),
        ],
      ),
    );
  }

  void _confirmResign() {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(S.t('resign')),
        content: Text(S.t('confirmResign')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(S.t('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F)),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              if (_isHotspot) {
                widget.net?.send(<String, dynamic>{'t': 'resign'});
              }
              _endGame(_winnerTitle(!whiteToMove), S.t('resignedSub'));
            },
            child: Text(S.t('confirm')),
          ),
        ],
      ),
    );
  }

  void _requestRematch() {
    if (_netDead) {
      _toast(S.t('opponentLeft'));
      return;
    }
    widget.net?.send(<String, dynamic>{'t': 'rematch_request'});
    _toast(S.t('rematchSent'));
  }

  void _sendBanter(String key) {
    final text = S.t(key);
    widget.net?.send(<String, dynamic>{'t': 'chat', 'text': text});
    _toast('${S.t('you')}: $text');
    _haptic();
  }

  // ---- Network message handling --------------------------------------------------

  void _onNetMsg(Map<String, dynamic> msg) {
    if (!mounted) return;
    try {
      switch (msg['t'] as String?) {
        case 'ready':
          if (widget.net != null && widget.net!.isHost) {
            widget.net!.send(<String, dynamic>{
              't': 'init',
              'pcm': opt.pawnCapture.index,
              'yifuta': opt.yifuta.index,
            });
          }
          break;
        case 'init':
          opt.pawnCapture = PawnCaptureMode.values[msg['pcm'] as int];
          opt.yifuta = YifutaMode.values[msg['yifuta'] as int];
          _netHandshakeDone = true;
          setState(() {});
          break;
        case 'move':
          _onRemoteMove(msg);
          break;
        case 'yifuta_decision':
          _applyYifutaDecision(msg['action'] as String);
          break;
        case 'chat':
          _toast('${S.t('opponent')}: ${msg['text'] as String? ?? ''}');
          _haptic();
          break;
        case 'rematch_request':
          _onRematchRequest();
          break;
        case 'rematch_reply':
          _onRematchReply((msg['accept'] as bool? ?? false));
          break;
        case 'resign':
          if (!_gameOver) {
            _endGame(_winnerTitle(!_iAmWhite), S.t('resignedSub'));
          }
          break;
        case 'disconnect':
          _onDisconnect();
          break;
        default:
          break;
      }
    } catch (_) {
      // Malformed message — ignore.
    }
  }

  void _onRemoteMove(Map<String, dynamic> msg) {
    if (_gameOver || _netDead) return;
    if (_yifCtx != null || _yifutaAwaitRemote) return;
    final moverWhite = !_iAmWhite;
    if (whiteToMove != moverWhite) return;
    try {
      final m = DamaMove(
        msg['from'] as int,
        (msg['steps'] as List).cast<int>(),
        (msg['captured'] as List).cast<int>(),
        (msg['promotes'] as bool? ?? false),
      );
      final legal = DamaEngine.legalMoves(board, moverWhite, opt,
          forceCaptureOnly: _forceLock);
      if (!legal.any((lm) => lm.sameAs(m))) return; // invalid — ignore
      if (m.isCapture) {
        DamaEngine.applyMove(board, m);
        _lastMove = m;
        if (moverWhite) {
          capturedByWhite += m.captured.length;
        } else {
          capturedByBlack += m.captured.length;
        }
        _quietPlies = 0;
        _haptic(heavy: true);
        if (m.promotes) _toast(S.t('promotedToast'));
        _finishTurnCommon();
      } else {
        final preBoard = List<int>.from(board);
        DamaEngine.applyMove(board, m);
        _lastMove = m;
        _handleQuietDone(m, preBoard, moverWhite, moveOriginLocal: false);
      }
    } catch (_) {
      // Malformed move — ignore.
    }
  }

  void _onRematchRequest() {
    if (_netDead) return;
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(S.t('rematchReqTitle')),
        content: Text(S.t('rematchReqBody')),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              widget.net
                  ?.send(<String, dynamic>{'t': 'rematch_reply', 'accept': false});
            },
            child: Text(S.t('decline')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              widget.net
                  ?.send(<String, dynamic>{'t': 'rematch_reply', 'accept': true});
              _resetBoard();
              _toast(S.t('gameStarted'));
            },
            child: Text(S.t('accept')),
          ),
        ],
      ),
    );
  }

  void _onRematchReply(bool accept) {
    if (accept) {
      _resetBoard();
      _toast(S.t('gameStarted'));
    } else {
      _toast(S.t('rematchDeclined'));
    }
  }

  void _onDisconnect() {
    if (_netDead) return;
    _netDead = true;
    _aiThinking = false;
    _aiToken++;
    if (!_gameOver) {
      _endGame(S.t('opponentLeft'), S.t('netEndedSub'));
    } else {
      setState(() {});
    }
  }

  void _toggleFlip() {
    setState(() => _flipped = !_flipped);
    _haptic();
  }

  // ---- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final boardMaxWidth = MediaQuery.of(context).size.width - 20;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            S.t('appTitle'),
            style: const TextStyle(
              color: Color(0xFFFFC107),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: S.t('newGame'),
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _confirmNewGame,
          ),
          if (widget.mode == GameMode.passPlay)
            IconButton(
              tooltip: S.t('flipBoard'),
              icon: const Icon(Icons.screen_rotation, color: Colors.white70),
              onPressed: _toggleFlip,
            ),
          IconButton(
            tooltip: S.t('resign'),
            icon: const Icon(Icons.flag_outlined, color: Colors.white70),
            onPressed: _confirmResign,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _statusPanel(),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: boardMaxWidth),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: AspectRatio(aspectRatio: 1, child: _boardWidget()),
                  ),
                ),
              ),
            ),
            _controlRow(),
          ],
        ),
      ),
    );
  }

  Widget _statusPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Column(
        children: [
          Row(
            children: [
              _miniPiece(whiteToMove),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _turnLabel(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _miniPiece(true),
              const SizedBox(width: 4),
              Text(
                '${12 - capturedByBlack}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 14),
              _miniPiece(false),
              const SizedBox(width: 4),
              Text(
                '${12 - capturedByWhite}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              S.t('remaining'),
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
            ),
          ),
          if (_aiThinking)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                color: Color(0xFFFFC107),
                backgroundColor: Color(0xFF262626),
              ),
            ),
          if (_forceLock && !_gameOver)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _pulseBanner(
                color: const Color(0xFFB71C1C),
                icon: Icons.local_fire_department,
                text: S.t('forcedBanner'),
              ),
            ),
          if (_yifutaAwaitRemote)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _pulseBanner(
                color: const Color(0xFF8D6E63),
                icon: Icons.hourglass_top,
                text: S.t('yifutaWaiting'),
              ),
            ),
          if (_netDead)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _staticBanner(
                color: const Color(0xFF7B1FA2),
                icon: Icons.wifi_off,
                text: S.t('opponentLeft'),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  String _turnLabel() {
    if (_gameOver) return _overTitle ?? '';
    if (_yifutaAwaitRemote) return S.t('yifutaWaiting');
    if (widget.mode == GameMode.vsAi) {
      if (_aiThinking) return S.t('aiThinking');
      if (whiteToMove) return S.t('yourTurn');
      return S.t('aiTurn');
    }
    if (_isHotspot) {
      return _isMyTurn() ? S.t('yourTurn') : S.t('opponentTurn');
    }
    return whiteToMove ? S.t('turnWhite') : S.t('turnBlack');
  }

  Widget _pulseBanner({
    required Color color,
    required IconData icon,
    required String text,
  }) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = 0.55 + 0.45 * _pulse.value;
        return Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: t.clamp(0.0, 1.0).toDouble()),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _staticBanner({
    required Color color,
    required IconData icon,
    required String text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniPiece(bool white) {
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: white
              ? const [Color(0xFFFFFFFF), Color(0xFF90A4AE)]
              : const [Color(0xFF616161), Color(0xFF111111)],
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
    );
  }

  // ---- Board -----------------------------------------------------------------

  Widget _boardWidget() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF3E2723),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2B1B17), width: 5),
        boxShadow: const [
          BoxShadow(
              color: Colors.black54, blurRadius: 12, offset: Offset(0, 5)),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AnimatedRotation(
          turns: _flipped ? 0.5 : 0.0,
          duration: const Duration(milliseconds: 350),
          child: _boardGrid(),
        ),
      ),
    );
  }

  Widget _boardGrid() {
    return Column(
      children: [
        for (int r = 0; r < 8; r++)
          Expanded(
            child: Row(
              children: [
                for (int c = 0; c < 8; c++)
                  Expanded(child: _cell(r, c)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(int r, int c) {
    final sq = square(r, c);
    final dark = ((r + c) & 1) == 1;
    final piece = board[sq];

    final isSel = _selected == sq;
    final destStep = _steps.cast<_StepOption?>().firstWhere(
          (s) => s!.to == sq,
          orElse: () => null,
        );
    final isVictim = _steps.any((s) => s.isCapture && s.victim == sq);
    final inPendingPath =
        _pending != null && (_pending!.from == sq || _pending!.steps.contains(sq));
    final isLastFrom = _lastMove != null && _lastMove!.from == sq;
    final isLastTo = _lastMove != null && _lastMove!.to == sq;
    final isForcedCapturer = _forceLock && _forcedCapturers.contains(sq);

    final baseColor =
        dark ? const Color(0xFF5D4037) : const Color(0xFFD7CCC8);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onTapSquare(sq),
      child: Container(
        color: baseColor,
        child: Stack(
          children: [
            if (isLastFrom)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                      color: const Color.fromRGBO(255, 193, 7, 0.15)),
                ),
              ),
            if (isLastTo)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                      color: const Color.fromRGBO(255, 193, 7, 0.28)),
                ),
              ),
            if (inPendingPath)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                      color: const Color.fromRGBO(255, 152, 0, 0.25)),
                ),
              ),
            if (piece != kEmpty)
              Positioned.fill(
                child: _pieceWidget(piece, forcedGlow: isForcedCapturer),
              ),
            if (isVictim)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFFF5252), width: 3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            if (isSel)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFFFC107), width: 3),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0xAAFFC107),
                            blurRadius: 8,
                            spreadRadius: 1),
                      ],
                    ),
                  ),
                ),
              ),
            if (destStep != null)
              Center(
                child: FractionallySizedBox(
                  widthFactor: 0.34,
                  heightFactor: 0.34,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: destStep.isCapture
                          ? const Color(0xCCFFAB40)
                          : const Color(0xCC26A69A),
                      boxShadow: [
                        BoxShadow(
                          color: (destStep.isCapture
                                  ? const Color(0xFFFFAB40)
                                  : const Color(0xFF26A69A))
                              .withValues(alpha: 0.8),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pieceWidget(int piece, {bool forcedGlow = false}) {
    final white = isWhitePiece(piece);
    final king = isKingPiece(piece);
    final core = Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          margin: const EdgeInsets.all(3.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.35, -0.35),
              radius: 1.05,
              colors: white
                  ? const [
                      Color(0xFFFFFFFF),
                      Color(0xFFCFD8DC),
                      Color(0xFF8D9AA3),
                    ]
                  : const [
                      Color(0xFF7E7E7E),
                      Color(0xFF3E3E3E),
                      Color(0xFF151515),
                    ],
              stops: const [0.0, 0.55, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: king
              ? const Padding(
                  padding: EdgeInsets.all(7),
                  child: AspectRatio(
                    aspectRatio: 1.5,
                    child: CustomPaint(painter: _CrownPainter()),
                  ),
                )
              : null,
        ),
      ),
    );
    if (forcedGlow) {
      return AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF1744)
                      .withValues(alpha: 0.30 + 0.55 * _pulse.value),
                  blurRadius: 7 + 7 * _pulse.value,
                  spreadRadius: 1 + 2 * _pulse.value,
                ),
              ],
            ),
            child: child,
          );
        },
        child: core,
      );
    }
    return core;
  }

  // ---- Control row -----------------------------------------------------------

  Widget _controlRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: 10,
        runSpacing: 6,
        children: [
          _CtrlButton(
            icon: Icons.undo,
            label: S.t('undo'),
            onTap: _undo,
          ),
          _CtrlButton(
            icon: Icons.refresh,
            label: S.t('newGame'),
            onTap: _confirmNewGame,
          ),
          if (_isHotspot)
            _CtrlButton(
              icon: Icons.chat_bubble_outline,
              label: S.t('banter'),
              onTap: _openBanterSheet,
            ),
          _CtrlButton(
            icon: Icons.home_outlined,
            label: S.t('backToMenu'),
            onTap: () => Navigator.of(context).maybePop(),
            color: const Color(0xFF26A69A),
          ),
        ],
      ),
    );
  }

  void _openBanterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.t('banterTitle'),
                  style: const TextStyle(
                    color: Color(0xFFFFC107),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final k in const [
                      'banter1',
                      'banter2',
                      'banter3',
                      'banter4',
                    ])
                      ActionChip(
                        label: Text(S.t(k)),
                        labelStyle: const TextStyle(
                            color: Colors.white, fontSize: 13),
                        backgroundColor: const Color(0xFF2A2A2A),
                        side: const BorderSide(color: Color(0xFFFFC107)),
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          _sendBanter(k);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- Game over -------------------------------------------------------------

  Future<void> _showGameOverDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              _overTitle ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFFC107),
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events,
                    color: Color(0xFFFFC107), size: 54),
                const SizedBox(height: 10),
                Text(
                  _overSub ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  Navigator.of(context).maybePop();
                },
                child: Text(S.t('backToMenu')),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  if (_isHotspot) {
                    _requestRematch();
                  } else {
                    _resetBoard();
                  }
                },
                child: Text(S.t('rematch')),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------------------------------
// Reusable widgets
// ----------------------------------------------------------------------------

class _CtrlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _CtrlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: const Color(0xFF1E1E1E),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(icon,
                    color: color ?? const Color(0xFFFFC107), size: 22),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hand-drawn golden crown for promoted kings (no image assets required).
class _CrownPainter extends CustomPainter {
  const _CrownPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final gold = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFE082), Color(0xFFFFC107), Color(0xFFB8860B)],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;

    final outline = Paint()
      ..color = const Color(0xFF5D4037)
      ..strokeWidth = (w * 0.035).clamp(0.8, 3.0).toDouble()
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(w * 0.10, h * 0.74)
      ..lineTo(w * 0.90, h * 0.74)
      ..lineTo(w * 0.90, h * 0.60)
      ..lineTo(w * 0.82, h * 0.28)
      ..lineTo(w * 0.66, h * 0.50)
      ..lineTo(w * 0.50, h * 0.20)
      ..lineTo(w * 0.34, h * 0.50)
      ..lineTo(w * 0.18, h * 0.28)
      ..lineTo(w * 0.10, h * 0.60)
      ..close();

    canvas.drawPath(path, gold);
    canvas.drawPath(path, outline);

    // Band at the base.
    final band = Paint()..color = const Color(0xFFFFC107);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.10, h * 0.78, w * 0.80, h * 0.13),
        Radius.circular(w * 0.03),
      ),
      band,
    );

    // Gems on the three tips.
    final gem = Paint()..color = const Color(0xFFFF5722);
    canvas.drawCircle(Offset(w * 0.18, h * 0.24), w * 0.045, gem);
    canvas.drawCircle(Offset(w * 0.50, h * 0.16), w * 0.052, gem);
    canvas.drawCircle(Offset(w * 0.82, h * 0.24), w * 0.045, gem);
  }

  @override
  bool shouldRepaint(covariant _CrownPainter oldDelegate) => false;
}
