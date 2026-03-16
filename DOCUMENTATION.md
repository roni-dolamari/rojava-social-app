# Rojava Kurdish Chat App — Documentation

## Overview

Rojava is a full-featured mobile chat application built with Flutter and Supabase as the backend. The app supports real-time messaging, voice and video calls, photo/video stories, a friend system, and a comprehensive security layer with device-based ban management and rate limiting. The UI supports two visual themes — Horizon (light) and Midnight Gradient (dark).

---

## Project Structure

```
lib/
├── main.dart
├── core/
│   ├── config/          # Supabase initialization
│   ├── constants/       # Colors, strings, assets, theme type
│   ├── theme/           # Material ThemeData definitions
│   └── widgets/         # Shared reusable widgets
├── data/
│   ├── model/           # Data models + FriendService
│   └── services/        # All backend service classes
└── features/
    ├── auth/            # Login, signup, auth controller
    ├── calls/           # Call history provider and screen
    ├── chat/            # Chat screen, controller, widgets
    ├── friends/         # Friend management screens and controller
    ├── home/            # Home screen and user profile screen
    ├── onboarding/      # Onboarding flow and theme selection
    ├── profile/         # Profile view and edit screens
    └── stories/         # Story creation, viewing, and management
```

---

## Architecture

The app follows a layered architecture:

```
UI Screens / Widgets
      ↓
Controllers (Riverpod StateNotifier)
      ↓
Services (business logic, Supabase calls)
      ↓
Supabase (database, auth, storage, realtime)
```

**State management** is handled by [Flutter Riverpod](https://riverpod.dev/). Each feature has a `StateNotifier` controller holding an immutable state object updated via `copyWith`. Providers expose both the service instances and the controllers to the widget tree.

---

## Entry Point — `main.dart`

On launch, the app:
1. Initializes Supabase via `SupabaseConfig.initialize()`.
2. Forces portrait orientation and sets the system UI overlay to transparent with light icons.
3. Checks whether onboarding has been completed and retrieves the saved theme preference.
4. Decides which initial screen to show: `OnboardingScreen`, `HomeScreen`, or `LoginScreen`.
5. Listens for banned-user state from `AuthController` and redirects to login with a ban message when triggered.

A global `navigatorKey` is used so that navigation can be triggered from outside the widget tree (e.g., from the ban listener).

---

## Core Layer

### `SupabaseConfig`
Holds the Supabase project URL and anon key as constants, initializes the Supabase client with PKCE auth flow, and exposes two static getters — `client` (the full `SupabaseClient`) and `auth` (the `GoTrueClient`) — so services can access them without passing instances around.

### `AppColors`
A single static class (private constructor, never instantiated) that defines the entire color palette as `Color` constants. Colors are organized into named groups:
- **Midnight** — dark theme colors (deep navy background, electric indigo primary, vivid violet secondary).
- **Horizon** — light theme colors (cool blue-tinted white background, bold royal indigo primary).
- **Semantic aliases** — `primary`, `background`, `surface`, `border` for use in widgets that don't need to be theme-aware.
- **Text colors** — separate sets for dark and light contexts.
- **Status colors** — `error`, `success`, `warning`, `info`.
- **Chart and onboarding accent colors**.

### `AppStrings`
A static-only class that centralizes all user-facing text used across the app: onboarding copy, theme names, auth field labels, validation messages, and success/error messages. Keeping strings here makes localization straightforward in the future.

### `AppAssets`
Defines all asset paths as constants. Animation files live in `assets/animations/` (Lottie JSON), images in `assets/images/`, and icons in `assets/icons/`. All paths are built by concatenating the base path constant with the filename.

### `AppThemeType`
A simple Dart `enum` with two values — `midnightGradient` and `horizon`. The `.value` getter returns the enum's name as a string, used when persisting the theme preference to `SharedPreferences`.

### `AppTheme`
Produces `ThemeData` objects for Material 3. `getTheme(AppThemeType)` is the single entry point that returns either `lightTheme` (Horizon) or `darkTheme` (Midnight Gradient). Both themes use the Inter font via `google_fonts`, configure color schemes from `AppColors`, and set consistent `CardTheme`, `ElevatedButtonTheme`, and `InputDecorationTheme` styles.

---

## Data Layer

### Models

Models are plain Dart classes. Each one follows the same pattern: named fields, a constructor, a `fromJson` factory for deserialization, optionally a `toJson` method for serialization, computed getters for derived values, and a `copyWith` method for immutable updates.

#### `UserModel` / `ProfileModel`
Both represent a user's profile record from the `profiles` table. Fields: `id`, `email`, `fullName`, `avatarUrl`, `bio`, `phone`, `createdAt`, `updatedAt`. `ProfileModel` is used in profile management contexts; `UserModel` is used in auth state. Both are structurally identical and support `copyWith`.

#### `MessageModel`
Represents a single chat message. The `messageType` field controls which kind of content is present:
- `'text'` — uses `content`.
- `'voice'` — uses `mediaUrl` and `mediaDuration` (seconds).
- `'image'` — uses `mediaUrl`, optionally `content` as a caption.
- `'location'` — uses `locationLat`, `locationLng`, `locationAddress`.
- `'live_location'` — same as location plus `liveLocationExpiresAt`.

Computed getters: `isMyMessage` compares `senderId` to the current auth user; `isLiveLocation` checks the type; `isLiveLocationActive` checks if the expiry time is still in the future. `senderName` and `senderAvatar` are populated by the service from a profile lookup, not stored on the message row itself.

#### `ConversationModel`
Represents a chat conversation as seen by the current user. The core row fields are `id`, `createdAt`, `updatedAt`, `lastMessageAt`. Additional fields — `otherUserName`, `otherUserAvatar`, `otherUserId`, `lastMessageContent`, `lastMessageType`, `unreadCount`, `isOnline` — are populated by the service by joining participant and message data before constructing the model.

#### `CallModel`
Represents a call record from the `calls` table. `callType` is `'voice'` or `'video'`; `status` is one of `'completed'`, `'missed'`, `'rejected'`, `'cancelled'`. The model includes profile data for both caller and receiver (`callerName`, `callerAvatar`, `receiverName`, `receiverAvatar`). Computed boolean getters (`isMissed`, `isCompleted`, etc.) simplify UI logic. `statusDisplay` returns a human-readable string. `formatDuration()` formats the `duration` (in seconds) as `"Xm Ys"`.

#### `FriendModel`
Represents a friendship record from the `friends` table. Core fields: `id`, `userId`, `friendId`, `createdAt`. The service populates `friendName`, `friendAvatar`, `friendEmail`, and `isOnline` from a profile lookup.

#### `FriendRequestModel`
Represents a pending, accepted, or rejected friend request. `status` is `'pending'`, `'accepted'`, or `'rejected'`. The service populates sender and receiver profile fields (`senderName`, `senderAvatar`, `senderEmail`, `receiverName`, `receiverAvatar`, `receiverEmail`) from joins.

#### `UserSearchModel`
Used specifically in search results. Contains basic profile info plus two relationship flags: `isFriend` (already friends) and `requestStatus` (any existing pending request). Computed getters `hasPendingRequest` and `canSendRequest` determine what action button to show in the search UI.

#### `StoryModel`
Represents a story from the `stories` table. `mediaType` is `'image'` or `'video'`. Stories expire after 24 hours; `expiresAt` is set by the database. `viewerIds` is a list populated from `story_views` records. Computed getters: `isExpired` checks current time against `expiresAt`; `isViewed` checks if `viewerIds` is non-empty. Supports full `copyWith`.

#### `ScheduledMessageModel`
Represents a message queued for future delivery in the `scheduled_messages` table. `messageType` is `'text'` or `'voice'`. For voice messages, `mediaUrl` and `mediaDuration` are set; for text messages, `content` holds the text. `isSent` is `false` until the scheduler delivers it.

#### `OnboardingPage`
A simple value object holding the content for a single onboarding slide: `title`, `description`, `animationPath` (Lottie), `primaryColor`, `secondaryColor`, and `gradientColors`. There are no database interactions — this data is defined statically in the onboarding controller.

#### `ThemeOption`
A value object used in the theme selection screen. Holds the theme's `name`, `icon`, `themeType` enum value, `gradientColors` for the preview card, and a `toastMessage` shown when the theme is selected.

---

### Services

Services are plain Dart classes that talk directly to Supabase. They do not hold state — all state lives in controllers.

#### `AuthService`
Handles sign-up, sign-in, sign-out, password reset, and profile fetching. Both `signUp` and `signIn` integrate with `BanCheckService` before and after the Supabase auth call:
- On sign-up: checks device ban, checks signup rate limit, registers the device, and logs the attempt.
- On sign-in: checks device ban, checks login rate limit, signs in, checks if the resulting user is banned (and immediately signs out if so), registers the device, and logs the attempt.

#### `ChatService`
The largest service. Covers the full messaging lifecycle:
- **Conversations**: `getOrCreateConversation` calls a Supabase RPC function; `getConversations` fetches participant and last-message data for each conversation in the list.
- **Messages**: `getMessages` fetches a conversation's non-deleted messages and batch-fetches sender profiles using `inFilter`. All send methods insert a row and return the full `MessageModel`.
- **Message types**: `sendTextMessage`, `sendVoiceMessage` (uploads to `chat-media` storage first), `sendImageMessage` (same), `sendLocationMessage`, `sendLiveLocationMessage`. Voice uploads can also be pre-uploaded via `uploadVoiceFile` and then sent with `sendPreuploadedVoiceMessage`.
- **Live location**: `updateLiveLocation` patches the message's coordinates; `stopLiveLocation` sets the expiry to now.
- **Read state**: `markAsRead` calls an RPC.
- **Real-time**: `subscribeToNewMessages` opens two Supabase Realtime channels for a conversation — one for `INSERT` events (new messages), one for `UPDATE` events (live location updates). Both feed into a single `broadcast` stream returned to the caller.
- **Calls**: `createCall` inserts a call record with status `'ringing'`; `updateCallStatus` patches the status and sets timestamps for `answered` and `ended`/`rejected`.

#### `BanCheckService`
Handles all security checks before authentication:
- **Device ban**: queries `banned_devices` table by device ID.
- **User ban**: checks the `is_banned` column in `profiles`.
- **Device registration**: upserts into `device_registry` with device info and a `last_seen` timestamp.
- **Signup rate limiting**: counts `signup_attempts` for the device in the last hour; blocks if ≥ 3.
- **Login rate limiting**: counts failed `login_attempts` for email + device in the last 15 minutes; blocks if ≥ 5.
- **`performPreAuthCheck`**: combines device-ban check and signup rate-limit check into a single call used by `AuthService` before sign-up.

#### `DeviceService`
Generates and persists a unique, hardware-derived device identifier:
- On Android: concatenates `androidId`, `device`, `model`, and `brand`, then SHA256-hashes the result.
- On iOS: SHA256-hashes `identifierForVendor`.
- The hash is stored in `SharedPreferences` so it survives app reinstalls within the same device vendor context.
- Raw hardware identifiers are never stored or transmitted — only the hash.
- `getDeviceInfo` returns a structured map of device metadata for storage in `device_registry`.

#### `CallService`
Manages call history independently of the WebRTC session:
- `getAllCalls` fetches call records with optional status filter, then batch-fetches caller and receiver profiles.
- `getCallStats` counts calls by status in a single query and returns a map of counts.
- `deleteCall` hard-deletes a single call record, using `.select('id')` to detect RLS-blocked deletes.
- `deleteAllCalls` deletes all calls where the current user is caller or receiver.

#### `WebRTCService`
Manages the full WebRTC peer connection lifecycle for voice and video calls:
- Uses three Google STUN servers and two OpenRelay TURN servers to ensure connectivity across NAT.
- **Signaling**: offers, answers, and ICE candidates are exchanged via rows inserted into the `call_signals` table and received through a Supabase Realtime `INSERT` subscription.
- **ICE candidate buffering**: candidates that arrive before the remote description is set are buffered and flushed once `setRemoteDescription` completes.
- **Caller flow**: `startCall` → initialize local stream → create peer connection → listen for signals → send offer.
- **Receiver flow**: `answerCall` → initialize local stream → create peer connection → set remote description (offer) → listen for signals → send answer.
- Exposes four broadcast streams: `localStream`, `remoteStream`, `callEnded`, `callConnected`.
- `toggleMute`, `toggleCamera`, `flipCamera`, `toggleSpeaker` are pass-through controls on the local media stream.

#### `StoryService`
Manages story creation, retrieval, and view tracking:
- `uploadStoryMedia` uploads the file to the `stories` Supabase Storage bucket and returns its public URL.
- `createStory` inserts a story row. The `expires_at` field is computed by the database (typically 24 hours after creation).
- `getAllStories` fetches only stories from friends (by first retrieving friend IDs), filters out expired ones, fetches each author's profile, checks which stories the current user has already viewed, and groups results by user ID.
- `getMyStories` fetches the current user's own stories and enriches each with its live view count.
- `markStoryAsViewed` inserts into `story_views`; duplicate-view errors are silently ignored.

#### `ScheduledMessageService`
Manages deferred message delivery:
- `scheduleMessage` and `scheduleVoiceMessage` insert rows into `scheduled_messages` with `is_sent: false`. Voice messages require the audio to be pre-uploaded and passed as a URL.
- `getPending` fetches all unsent scheduled messages for a conversation ordered by `scheduled_at`.
- `cancel` hard-deletes a scheduled message.
- `sendDueMessages` queries for messages whose `scheduled_at` has passed, sends each one via `ChatService`, and marks them `is_sent: true`. Failed sends are silently skipped to retry on the next tick.

#### `FriendService` (`data/model/friend_service.dart`)
Handles the social graph:
- `searchUsers` performs a case-insensitive partial match on `full_name`, then for each result checks friendship status and pending request status.
- `sendFriendRequest` / `cancelFriendRequest` insert or delete from `friend_requests`.
- `getReceivedRequests` / `getSentRequests` fetch pending requests and populate sender/receiver profile data.
- `acceptFriendRequest` / `rejectFriendRequest` delegate to Supabase RPC functions that handle the bidirectional friendship insert atomically.
- `getFriends` fetches the `friends` table for the current user and populates each entry with the friend's profile.
- `removeFriend` calls an RPC that removes both directions of the friendship.

---

## Features Layer

### Authentication (`features/auth/`)

**`AuthState`** holds: `user` (the signed-in `UserModel`), `isLoading`, `error`, and `isBanned`.

**`AuthController`** (`StateNotifier<AuthState>`) is the single source of truth for authentication:
- On construction, it checks if a Supabase session already exists and loads the profile.
- After every successful sign-in or sign-up it starts a **ban polling timer** that queries the `profiles` table every 10 seconds. If `is_banned` is found to be `true`, it calls `_forceSignOut`, which clears state, signs out of Supabase, and sets `isBanned: true` — which `main.dart` listens for to redirect to login.
- `signUp`, `signIn`, `signOut`, `resetPassword` are simple async wrappers around `AuthService` that update the loading/error state accordingly.

### Chat (`features/chat/`)

**`ChatState`** holds: `conversations`, `messages`, `isLoading`, `isSending`, `error`, `currentConversationId`.

**`ChatController`** (`StateNotifier<ChatState>`) manages the full chat experience:
- `loadConversations` fetches the list and stores it in state.
- `loadMessages` loads messages for a conversation, cancels any previous real-time subscription, subscribes to new and updated messages, and marks the conversation as read in the background. Incoming real-time messages are deduped before appending to state.
- `sendTextMessage`, `sendVoiceMessage`, `sendImageMessage`, `sendLocationMessage` each set `isSending: true`, call the corresponding `ChatService` method, and dedup-append the returned message to state.
- `deleteMessage` removes the message from local state optimistically after a successful service call.
- `startCall` delegates to `ChatService.createCall` and returns the new call ID.

**`VoiceRecorderWidget`** handles in-chat audio recording. It requests microphone permission, records using the `record` package, shows a waveform animation while recording, and passes the resulting audio file to the chat controller on completion.

**`MessageBubble`** renders a single message. It switches on `messageType` to render text, voice player, image, location map thumbnail, or live location with an active/expired indicator. Bubbles are right-aligned for the current user and left-aligned for others.

**`ScheduledMessagesSheet`** is a bottom sheet that lists pending scheduled messages for the current conversation, allows cancellation, and provides a form to schedule a new text message at a chosen date and time.

### Calls (`features/calls/`)

**`callsProvider`** is a `FutureProvider.family<List<CallModel>, String?>` that fetches calls filtered by an optional status. **`callStatsProvider`** is a `FutureProvider<Map<String, int>>` for the aggregated statistics. Both are backed by `CallService`.

The **Calls Screen** displays call history grouped by status (all, missed, completed, rejected), shows per-call metadata including duration and participant avatars, and provides delete controls.

### Friends (`features/friends/`)

**`FriendController`** manages: friends list, received requests, sent requests, and search results. Each list is stored separately in the state object. Methods delegate to `FriendService` and update state on success or set an error.

The feature has three screens:
- **Search Users** — live search with debounce, shows add/pending/already-friend states.
- **Friend Requests** — tabs for received and sent requests with accept/reject/cancel actions.
- **Add Friend / Friend detail** — shows a user's profile with the appropriate friend action.

### Stories (`features/stories/`)

**`StoryController`** holds: a map of grouped friend stories, the current user's own stories, loading state, and error. Methods wrap `StoryService` calls and refresh state.

The feature has three screens:
- **Create Story** — picks an image or video from the gallery, shows a preview, and uploads on confirm.
- **Story Viewer** — fullscreen story playback with progress bars, tap-to-advance, and swipe-to-close. Marks stories as viewed as they are displayed.
- **Story Views** — shows the list of users who viewed one of the current user's stories.

### Home (`features/home/`)

The **Home Screen** is the main tab shell. It integrates the conversations list, the stories row, a friend quick-access panel, and a notification badge for pending friend requests. It watches the `chatControllerProvider` for conversation updates.

**User Profile Screen** displays another user's public profile, their stories, mutual-friend count, and allows starting a chat or adjusting the friendship.

### Profile (`features/profile/`)

**`ProfileController`** holds the current user's `ProfileModel` and a loading/error state. It exposes `loadProfile`, `updateProfile` (name, bio, phone), `uploadAvatar`, and `deleteAvatar`. Avatar uploads go to the `avatars` Supabase Storage bucket.

### Onboarding (`features/onboarding/`)

**`OnboardingController`** manages the selected theme and persists it to `SharedPreferences`. It also exposes static methods `isOnboardingCompleted` and `getSavedTheme` for use at app startup (before the Riverpod tree is fully initialized).

The onboarding flow has a page-view of slides (animated with Lottie) followed by a theme selection screen where the user picks Horizon or Midnight Gradient. Completing onboarding writes a `completed` flag to `SharedPreferences`.

---

## Database Tables (Supabase)

| Table | Purpose |
|---|---|
| `profiles` | User profile data + `is_banned` flag |
| `conversations` | Chat conversation records |
| `conversation_participants` | Many-to-many: users ↔ conversations |
| `messages` | All message types including location and voice |
| `friends` | Bidirectional friendship rows |
| `friend_requests` | Pending/accepted/rejected requests |
| `stories` | Story media records with expiry |
| `story_views` | Which user viewed which story |
| `calls` | Call history with status and duration |
| `call_signals` | WebRTC signaling data (offer, answer, ICE) |
| `banned_devices` | Device IDs blocked from the app |
| `device_registry` | Devices registered per user |
| `signup_attempts` | Rate-limiting log for registrations |
| `login_attempts` | Rate-limiting log for logins |
| `scheduled_messages` | Queued messages pending delivery |

**Supabase Storage Buckets**:
- `avatars` — profile pictures
- `chat-media` — voice messages and images sent in chat
- `stories` — story media files

**RPC Functions** called by the app:
- `get_or_create_conversation(other_user_id)` — finds or creates a 1-to-1 conversation
- `get_unread_count(conv_id)` — returns the unread message count for the current user
- `mark_as_read(conv_id)` — marks all messages as read for the current user
- `accept_friend_request(request_id)` — atomically inserts both friendship rows
- `reject_friend_request(request_id)` — sets request status to rejected
- `remove_friend(target_friend_id)` — removes both directions of a friendship
- `get_user_email(user_id)` — returns a user's email for display in friend search

---

## Key Dependencies

| Package | Purpose |
|---|---|
| `supabase_flutter` | Backend: database, auth, storage, realtime |
| `flutter_riverpod` | State management |
| `flutter_webrtc` | Peer-to-peer voice and video calls |
| `record` | Audio recording for voice messages |
| `audioplayers` | Audio playback for received voice messages |
| `image_picker` | Selecting images and videos from the gallery/camera |
| `video_player` | Playing video stories |
| `geolocator` | Fetching GPS coordinates for location messages |
| `device_info_plus` | Reading hardware identifiers for device ID generation |
| `crypto` | SHA256 hashing of device identifiers |
| `shared_preferences` | Persisting onboarding state, theme choice, device ID |
| `cached_network_image` | Efficient network image loading with disk cache |
| `lottie` | Lottie animation playback in onboarding |
| `google_fonts` | Inter typeface across both themes |
| `permission_handler` | Requesting microphone, camera, and location permissions |
