//
//  MailCoreObjCBridge.h
//  react-native-mail-engine
//
//  A thin Objective-C (NOT Objective-C++) facade over MailCore2.
//
//  WHY THIS EXISTS
//  ---------------
//  `mailcore2-ios` ships an Objective-C++ umbrella header (`<MailCore/MailCore.h>`)
//  whose public headers transitively `#include` C++ STL headers (e.g. MCObject is
//  declared in headers that pull in <string>, <vector>, ...). Swift can import
//  Objective-C, but it CANNOT import Objective-C++. Importing MailCore directly
//  from Swift (even with C++ interop enabled) is therefore unreliable and breaks
//  module verification.
//
//  This header exposes ONLY plain Foundation types (NSString, NSData, NSNumber,
//  NSArray, NSDictionary, blocks) and opaque object handles. It contains no C++
//  whatsoever, so it is safe to surface to this pod's Swift code: the podspec
//  declares it in `public_header_files`, so it lands in the pod's generated
//  module umbrella and same-target Swift can use these classes directly (no
//  bridging header — bridging headers aren't usable for a `DEFINES_MODULE` pod).
//  The implementation lives in `MailCoreObjCBridge.mm`, which IS compiled as
//  Objective-C++ and is the only place that talks to MailCore2 directly.
//
//  All blocking IMAP/SMTP work is performed inside these methods. The Swift layer
//  wraps each call in a Nitro `Promise.parallel(...)` so the JS thread never blocks.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Coded error domain

/// All NSErrors produced by the bridge use this domain. `userInfo[RNMailEngineErrorCodeKey]`
/// carries the stable `ERR_*` string that JS maps to `MailError.code`.
extern NSString *const RNMailEngineErrorDomain;
extern NSString *const RNMailEngineErrorCodeKey;

#pragma mark - Plain data carriers (no C++)

/// A parsed email address (display name optional).
@interface RNMailAddress : NSObject
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, copy) NSString *email;
@end

/// A mailbox / IMAP folder.
@interface RNMailbox : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *delimiter;   // single char, or "" if none
@property (nonatomic, copy) NSArray<NSString *> *flags;
@property (nonatomic, assign) BOOL selectable;
@property (nonatomic, strong, nullable) NSNumber *exists;  // nil if unknown
@property (nonatomic, strong, nullable) NSNumber *unseen;  // nil if unknown
@end

/// Folder STATUS values returned by `selectFolderPath:`.
@interface RNFolderStatus : NSObject
@property (nonatomic, assign) uint32_t messageCount;  // EXISTS
@property (nonatomic, assign) uint32_t unseenCount;   // UNSEEN
@property (nonatomic, assign) uint32_t uidNext;       // UIDNEXT
@property (nonatomic, assign) uint32_t uidValidity;   // UIDVALIDITY
@end

/// Envelope + flags for one message (no body).
@interface RNMessageHeader : NSObject
@property (nonatomic, assign) uint32_t uid;
@property (nonatomic, copy, nullable) NSString *messageId;
@property (nonatomic, copy, nullable) NSString *subject;
@property (nonatomic, copy) NSArray<RNMailAddress *> *from;
@property (nonatomic, copy) NSArray<RNMailAddress *> *to;
@property (nonatomic, copy) NSArray<RNMailAddress *> *cc;
@property (nonatomic, copy) NSArray<RNMailAddress *> *bcc;
@property (nonatomic, copy) NSArray<RNMailAddress *> *replyTo;
@property (nonatomic, strong, nullable) NSNumber *dateMs;  // epoch ms, nil if unparseable
@property (nonatomic, copy) NSArray<NSString *> *flags;
@property (nonatomic, strong, nullable) NSNumber *size;    // bytes, nil if unknown
@property (nonatomic, assign) BOOL hasAttachments;
@property (nonatomic, copy, nullable) NSString *inReplyTo;
@property (nonatomic, copy) NSArray<NSString *> *references;
@property (nonatomic, copy, nullable) NSString *preview;
@end

/// One attachment / inline resource on a parsed message.
@interface RNAttachment : NSObject
@property (nonatomic, copy, nullable) NSString *partId;
@property (nonatomic, copy, nullable) NSString *filename;
@property (nonatomic, copy) NSString *mimeType;
@property (nonatomic, assign) NSUInteger size;
@property (nonatomic, copy, nullable) NSString *contentId;
@property (nonatomic, assign) BOOL isInline;
@property (nonatomic, strong, nullable) NSData *data;  // decoded bytes (may be nil)
@end

/// A fully parsed message.
@interface RNMessage : NSObject
@property (nonatomic, strong) RNMessageHeader *header;
@property (nonatomic, copy, nullable) NSString *textBody;
@property (nonatomic, copy, nullable) NSString *htmlBody;
@property (nonatomic, copy) NSArray<RNAttachment *> *attachments;
@end

/// An attachment to send.
@interface RNOutgoingAttachment : NSObject
@property (nonatomic, copy) NSString *filename;
@property (nonatomic, copy, nullable) NSString *mimeType;
@property (nonatomic, copy, nullable) NSString *path;       // file:// or absolute path
@property (nonatomic, strong, nullable) NSData *data;       // inline bytes
@property (nonatomic, copy, nullable) NSString *contentId;
@property (nonatomic, assign) BOOL isInline;
@end

/// A message to send over SMTP.
@interface RNOutgoingMessage : NSObject
@property (nonatomic, strong, nullable) RNMailAddress *from;
@property (nonatomic, copy) NSArray<RNMailAddress *> *to;
@property (nonatomic, copy) NSArray<RNMailAddress *> *cc;
@property (nonatomic, copy) NSArray<RNMailAddress *> *bcc;
@property (nonatomic, copy) NSArray<RNMailAddress *> *replyTo;
@property (nonatomic, copy) NSString *subject;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy, nullable) NSString *html;
@property (nonatomic, copy) NSArray<RNOutgoingAttachment *> *attachments;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *customHeaders;
@property (nonatomic, copy, nullable) NSString *inReplyTo;
@property (nonatomic, copy) NSArray<NSString *> *references;
@end

/// Search terms (ANDed). Booleans use NSNumber so they can be left unset (nil).
@interface RNSearchCriteria : NSObject
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy, nullable) NSString *from;
@property (nonatomic, copy, nullable) NSString *to;
@property (nonatomic, copy, nullable) NSString *subject;
@property (nonatomic, copy, nullable) NSString *body;
@property (nonatomic, strong, nullable) NSNumber *seen;      // BOOL
@property (nonatomic, strong, nullable) NSNumber *flagged;   // BOOL
@property (nonatomic, strong, nullable) NSNumber *answered;  // BOOL
@property (nonatomic, strong, nullable) NSNumber *sinceDateMs;
@property (nonatomic, strong, nullable) NSNumber *beforeDateMs;
@property (nonatomic, strong, nullable) NSNumber *uidRangeStart;
@property (nonatomic, strong, nullable) NSNumber *uidRangeEnd;
@end

#pragma mark - Session handles

/// Opaque wrapper around an `MCOIMAPSession` (+ optional `MCOSMTPSession`).
/// All methods are SYNCHRONOUS/blocking and must be invoked from a background
/// thread (the Swift layer does this via `Promise.parallel`). MailCore's own
/// operations are run to completion synchronously inside the bridge.
@interface RNMailSession : NSObject

/// Build the session and validate IMAP auth (runs a login/check operation).
/// SMTP, when configured, is validated lazily on the first `sendMessage:`.
/// Returns nil and populates `error` on IMAP connect/auth failure.
/// `securityImap`/`securitySmtp`: 0 = plain, 1 = starttls, 2 = tls(implicit SSL).
/// `authType`: 0 = password, 1 = xoauth2, 2 = oauthbearer (sasl XOAUTH2/OAUTHBEARER).
+ (nullable instancetype)connectWithImapHost:(NSString *)imapHost
                                    imapPort:(uint32_t)imapPort
                                securityImap:(int)securityImap
                          allowInvalidImapTls:(BOOL)allowInvalidImapTls
                                    smtpHost:(nullable NSString *)smtpHost
                                    smtpPort:(uint32_t)smtpPort
                                securitySmtp:(int)securitySmtp
                          allowInvalidSmtpTls:(BOOL)allowInvalidSmtpTls
                                    authType:(int)authType
                                    username:(NSString *)username
                                    password:(nullable NSString *)password
                                 accessToken:(nullable NSString *)accessToken
                           connectTimeoutSec:(NSTimeInterval)connectTimeoutSec
                                       error:(NSError * _Nullable * _Nullable)error;

@property (nonatomic, readonly) BOOL hasSmtp;

// --- Account-level (IMAP) ---
- (nullable NSArray<RNMailbox *> *)listMailboxesWithError:(NSError * _Nullable * _Nullable)error;
- (nullable RNFolderStatus *)selectFolderPath:(NSString *)path
                                        error:(NSError * _Nullable * _Nullable)error;
- (BOOL)createFolderPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error;
- (BOOL)deleteFolderPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error;
- (BOOL)renameFolderPath:(NSString *)path
                  toPath:(NSString *)newPath
                   error:(NSError * _Nullable * _Nullable)error;
- (BOOL)noopWithError:(NSError * _Nullable * _Nullable)error;

// --- SMTP ---
- (BOOL)sendMessage:(RNOutgoingMessage *)message error:(NSError * _Nullable * _Nullable)error;

// --- Mailbox-level (IMAP); `folderPath` selects the working folder per call ---

/// Fetch headers for `uids` (already filtered/limited by the caller). When `uids`
/// is nil, fetches the full UID range `1:*` then the caller slices it.
- (nullable NSArray<RNMessageHeader *> *)fetchHeadersInFolder:(NSString *)folderPath
                                                        uids:(nullable NSArray<NSNumber *> *)uids
                                                       error:(NSError * _Nullable * _Nullable)error;

/// Returns the full set of UIDs in `folderPath` (sorted ascending), for slicing.
- (nullable NSArray<NSNumber *> *)allUidsInFolder:(NSString *)folderPath
                                            error:(NSError * _Nullable * _Nullable)error;

- (nullable RNMessage *)fetchMessageInFolder:(NSString *)folderPath
                                         uid:(uint32_t)uid
                          includeAttachments:(BOOL)includeAttachments
                           maxAttachmentBytes:(int64_t)maxAttachmentBytes
                                    markSeen:(BOOL)markSeen
                                       error:(NSError * _Nullable * _Nullable)error;

- (nullable NSData *)fetchAttachmentInFolder:(NSString *)folderPath
                                         uid:(uint32_t)uid
                                      partId:(NSString *)partId
                                       error:(NSError * _Nullable * _Nullable)error;

- (nullable NSArray<NSNumber *> *)searchInFolder:(NSString *)folderPath
                                        criteria:(RNSearchCriteria *)criteria
                                           error:(NSError * _Nullable * _Nullable)error;

/// `mode`: 0 = add, 1 = remove, 2 = set. Flags are bare names ("\\Seen", "\\Flagged", ...).
- (BOOL)storeFlagsInFolder:(NSString *)folderPath
                      uids:(NSArray<NSNumber *> *)uids
                     flags:(NSArray<NSString *> *)flags
                      mode:(int)mode
                     error:(NSError * _Nullable * _Nullable)error;

- (BOOL)copyMessagesInFolder:(NSString *)folderPath
                        uids:(NSArray<NSNumber *> *)uids
                 destination:(NSString *)destination
                       error:(NSError * _Nullable * _Nullable)error;

- (BOOL)moveMessagesInFolder:(NSString *)folderPath
                        uids:(NSArray<NSNumber *> *)uids
                 destination:(NSString *)destination
                       error:(NSError * _Nullable * _Nullable)error;

- (BOOL)deleteMessagesInFolder:(NSString *)folderPath
                          uids:(NSArray<NSNumber *> *)uids
                       expunge:(BOOL)expunge
                         error:(NSError * _Nullable * _Nullable)error;

// --- IDLE ---

/// YES if the server advertised the IDLE capability on this connection.
- (BOOL)serverSupportsIdle;

/// Blocks until new mail arrives, `stopIdle` is called, or an error occurs.
/// On a wake-up caused by new mail, `onMail` is invoked with the new UIDs + EXISTS
/// and this method returns YES. On `stopIdle()` it returns YES with no callback.
/// On error it returns NO and populates `error`.
- (BOOL)idleOnceInFolder:(NSString *)folderPath
                lastKnownUid:(uint32_t)lastKnownUid
                      onMail:(void (^)(NSArray<NSNumber *> *uids, uint32_t exists))onMail
                       error:(NSError * _Nullable * _Nullable)error;

/// Interrupts a blocking `idleOnceInFolder:` from another thread.
- (void)interruptIdle;

- (void)disconnect;

@end

NS_ASSUME_NONNULL_END
