//
//  MailCoreObjCBridge.mm
//  react-native-mail-engine
//
//  Objective-C++ implementation of the MailCore2 facade declared in
//  MailCoreObjCBridge.h. This is the ONLY translation unit that imports MailCore;
//  everything above it (Swift) sees only the plain-Foundation interface.
//
//  MailCore2's operations are asynchronous (op.start:^{...}). Each facade method
//  drives one operation to completion synchronously via a dispatch_semaphore, so
//  the Swift layer can call it from a `Promise.parallel(...)` background thread.
//

#import "MailCoreObjCBridge.h"
#import <MailCore/MailCore.h>

NSString *const RNMailEngineErrorDomain = @"RNMailEngine";
NSString *const RNMailEngineErrorCodeKey = @"RNMailEngineErrorCode";

#pragma mark - Error helpers

static NSError *RNMakeError(NSString *code, NSString *message) {
  return [NSError errorWithDomain:RNMailEngineErrorDomain
                             code:0
                         userInfo:@{
                           RNMailEngineErrorCodeKey: code ?: @"ERR_IMAP",
                           NSLocalizedDescriptionKey: message ?: @"Unknown mail engine error"
                         }];
}

/// Map a MailCore NSError to one of our stable ERR_* codes.
static NSError *RNMapMailCoreError(NSError *err, NSString *fallbackCode) {
  if (err == nil) return nil;
  MCOErrorCode mc = (MCOErrorCode)err.code;
  NSString *code = fallbackCode ?: @"ERR_IMAP";
  switch (mc) {
    case MCOErrorAuthentication:
    case MCOErrorGmailIMAPNotEnabled:
    case MCOErrorAuthenticationRequired:
      code = @"ERR_AUTH"; break;
    case MCOErrorConnection:
    case MCOErrorTLSNotAvailable:
      code = (mc == MCOErrorTLSNotAvailable) ? @"ERR_TLS" : @"ERR_CONNECT"; break;
    case MCOErrorCertificate:
      code = @"ERR_TLS"; break;
    case MCOErrorParse:
      code = @"ERR_PARSE"; break;
    case MCOErrorNoSender:
    case MCOErrorNoRecipient:
    case MCOErrorSMTPNotSupported:
      code = @"ERR_SMTP"; break;
    default:
      break;
  }
  return RNMakeError(code, err.localizedDescription ?: @"Mail server error");
}

#pragma mark - Plain data carriers

@implementation RNMailAddress @end
@implementation RNMailbox @end
@implementation RNFolderStatus @end
@implementation RNMessageHeader @end
@implementation RNAttachment @end
@implementation RNMessage @end
@implementation RNOutgoingAttachment @end
@implementation RNOutgoingMessage @end
@implementation RNSearchCriteria @end

#pragma mark - Conversion helpers

static MCOConnectionType RNConnectionType(int security) {
  switch (security) {
    case 0: return MCOConnectionTypeClear;
    case 1: return MCOConnectionTypeStartTLS;
    default: return MCOConnectionTypeTLS; // 2 = implicit SSL
  }
}

static RNMailAddress *RNAddressFromMCO(MCOAddress *a) {
  RNMailAddress *out = [RNMailAddress new];
  out.name = a.displayName;
  out.email = a.mailbox ?: @"";
  return out;
}

static NSArray<RNMailAddress *> *RNAddressesFromMCO(NSArray<MCOAddress *> *addrs) {
  NSMutableArray *out = [NSMutableArray array];
  for (MCOAddress *a in addrs) [out addObject:RNAddressFromMCO(a)];
  return out;
}

static MCOAddress *RNMCOFromAddress(RNMailAddress *a) {
  if (a.name.length > 0) {
    return [MCOAddress addressWithDisplayName:a.name mailbox:a.email];
  }
  return [MCOAddress addressWithMailbox:a.email];
}

static NSArray<MCOAddress *> *RNMCOFromAddresses(NSArray<RNMailAddress *> *addrs) {
  NSMutableArray *out = [NSMutableArray array];
  for (RNMailAddress *a in addrs) [out addObject:RNMCOFromAddress(a)];
  return out;
}

/// Translate MailCore flag bits into the IMAP keyword strings JS expects.
static NSArray<NSString *> *RNFlagNames(MCOMessageFlag flags) {
  NSMutableArray *out = [NSMutableArray array];
  if (flags & MCOMessageFlagSeen) [out addObject:@"\\Seen"];
  if (flags & MCOMessageFlagFlagged) [out addObject:@"\\Flagged"];
  if (flags & MCOMessageFlagDeleted) [out addObject:@"\\Deleted"];
  if (flags & MCOMessageFlagAnswered) [out addObject:@"\\Answered"];
  if (flags & MCOMessageFlagDraft) [out addObject:@"\\Draft"];
  if (flags & MCOMessageFlagForwarded) [out addObject:@"$Forwarded"];
  return out;
}

/// Parse IMAP keyword strings back into a MailCore flag bitmask.
static MCOMessageFlag RNFlagMask(NSArray<NSString *> *names) {
  MCOMessageFlag mask = MCOMessageFlagNone;
  for (NSString *raw in names) {
    NSString *n = raw.lowercaseString;
    if ([n containsString:@"seen"]) mask |= MCOMessageFlagSeen;
    else if ([n containsString:@"flagged"]) mask |= MCOMessageFlagFlagged;
    else if ([n containsString:@"deleted"]) mask |= MCOMessageFlagDeleted;
    else if ([n containsString:@"answered"]) mask |= MCOMessageFlagAnswered;
    else if ([n containsString:@"draft"]) mask |= MCOMessageFlagDraft;
  }
  return mask;
}

static NSNumber *_Nullable RNDateMs(NSDate *_Nullable date) {
  if (date == nil) return nil;
  return @((int64_t)(date.timeIntervalSince1970 * 1000.0));
}

static MCOIndexSet *RNIndexSetFromUids(NSArray<NSNumber *> *uids) {
  MCOIndexSet *set = [MCOIndexSet indexSet];
  for (NSNumber *u in uids) [set addIndex:u.unsignedLongLongValue];
  return set;
}

#pragma mark - Session

@implementation RNMailSession {
  MCOIMAPSession *_imap;
  MCOSMTPSession *_Nullable _smtp;
  MCOIMAPIdleOperation *_Nullable _idleOp;
}

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
                                       error:(NSError **)error {
  RNMailSession *session = [RNMailSession new];

  MCOIMAPSession *imap = [[MCOIMAPSession alloc] init];
  imap.hostname = imapHost;
  imap.port = imapPort;
  imap.connectionType = RNConnectionType(securityImap);
  imap.username = username;
  imap.timeout = connectTimeoutSec > 0 ? connectTimeoutSec : 30;
  imap.checkCertificateEnabled = !allowInvalidImapTls;
  if (authType == 0) {
    imap.password = password ?: @"";
  } else {
    imap.OAuth2Token = accessToken ?: @"";
    imap.authType = (authType == 2) ? MCOAuthTypeXOAuth2Outlook : MCOAuthTypeXOAuth2;
  }
  session->_imap = imap;

  if (smtpHost.length > 0) {
    MCOSMTPSession *smtp = [[MCOSMTPSession alloc] init];
    smtp.hostname = smtpHost;
    smtp.port = smtpPort;
    smtp.connectionType = RNConnectionType(securitySmtp);
    smtp.username = username;
    smtp.timeout = connectTimeoutSec > 0 ? connectTimeoutSec : 30;
    smtp.checkCertificateEnabled = !allowInvalidSmtpTls;
    if (authType == 0) {
      smtp.password = password ?: @"";
    } else {
      smtp.OAuth2Token = accessToken ?: @"";
      smtp.authType = (authType == 2) ? MCOAuthTypeXOAuth2Outlook : MCOAuthTypeXOAuth2;
    }
    session->_smtp = smtp;
  }

  // Validate auth eagerly so `connect()` fails fast with a clean code.
  __block NSError *loginError = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  MCOIMAPOperation *check = [imap checkAccountOperation];
  [check start:^(NSError *err) {
    loginError = err;
    dispatch_semaphore_signal(sem);
  }];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

  if (loginError != nil) {
    if (error) *error = RNMapMailCoreError(loginError, @"ERR_CONNECT");
    return nil;
  }
  return session;
}

- (BOOL)hasSmtp { return _smtp != nil; }

#pragma mark - Operation runner

/// Run an IMAP operation that yields `(NSError *)`-only completion synchronously.
- (BOOL)runVoidOp:(MCOIMAPOperation *)op
        fallback:(NSString *)fallbackCode
            error:(NSError **)error {
  if (op == nil) {
    if (error) *error = RNMakeError(@"ERR_IMAP", @"Could not create IMAP operation");
    return NO;
  }
  __block NSError *opError = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  [op start:^(NSError *err) {
    opError = err;
    dispatch_semaphore_signal(sem);
  }];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
  if (opError != nil) {
    if (error) *error = RNMapMailCoreError(opError, fallbackCode);
    return NO;
  }
  return YES;
}

#pragma mark - Account-level

- (nullable NSArray<RNMailbox *> *)listMailboxesWithError:(NSError **)error {
  __block NSError *opError = nil;
  __block NSArray<MCOIMAPFolder *> *folders = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  MCOIMAPFetchFoldersOperation *op = [_imap fetchAllFoldersOperation];
  [op start:^(NSError *err, NSArray<MCOIMAPFolder *> *result) {
    opError = err;
    folders = result;
    dispatch_semaphore_signal(sem);
  }];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
  if (opError != nil) {
    if (error) *error = RNMapMailCoreError(opError, @"ERR_IMAP");
    return nil;
  }

  NSMutableArray<RNMailbox *> *out = [NSMutableArray array];
  for (MCOIMAPFolder *f in folders) {
    RNMailbox *box = [RNMailbox new];
    NSString *delimiter = f.delimiter ? [NSString stringWithFormat:@"%c", f.delimiter] : @"";
    box.path = f.path ?: @"";
    NSArray<NSString *> *parts = delimiter.length > 0 ? [box.path componentsSeparatedByString:delimiter] : @[box.path];
    box.name = parts.lastObject ?: box.path;
    box.delimiter = delimiter;
    box.selectable = (f.flags & MCOIMAPFolderFlagNoSelect) == 0;
    NSMutableArray<NSString *> *flagNames = [NSMutableArray array];
    if (f.flags & MCOIMAPFolderFlagHasChildren) [flagNames addObject:@"\\HasChildren"];
    if (f.flags & MCOIMAPFolderFlagNoSelect) [flagNames addObject:@"\\Noselect"];
    if (f.flags & MCOIMAPFolderFlagSentMail) [flagNames addObject:@"\\Sent"];
    if (f.flags & MCOIMAPFolderFlagDrafts) [flagNames addObject:@"\\Drafts"];
    if (f.flags & MCOIMAPFolderFlagAllMail) [flagNames addObject:@"\\All"];
    if (f.flags & MCOIMAPFolderFlagTrash) [flagNames addObject:@"\\Trash"];
    if (f.flags & MCOIMAPFolderFlagSpam) [flagNames addObject:@"\\Junk"];
    box.flags = flagNames;
    [out addObject:box];
  }
  return out;
}

- (nullable RNFolderStatus *)selectFolderPath:(NSString *)path error:(NSError **)error {
  __block NSError *opError = nil;
  __block MCOIMAPFolderStatus *status = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  MCOIMAPFolderStatusOperation *op = [_imap folderStatusOperation:path];
  [op start:^(NSError *err, MCOIMAPFolderStatus *result) {
    opError = err;
    status = result;
    dispatch_semaphore_signal(sem);
  }];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
  if (opError != nil) {
    if (error) *error = RNMapMailCoreError(opError, @"ERR_MAILBOX");
    return nil;
  }
  RNFolderStatus *out = [RNFolderStatus new];
  out.messageCount = status.messageCount;
  out.unseenCount = status.unseenCount;
  out.uidNext = status.uidNext;
  out.uidValidity = status.uidValidity;
  return out;
}

- (BOOL)createFolderPath:(NSString *)path error:(NSError **)error {
  return [self runVoidOp:[_imap createFolderOperation:path] fallback:@"ERR_MAILBOX" error:error];
}
- (BOOL)deleteFolderPath:(NSString *)path error:(NSError **)error {
  return [self runVoidOp:[_imap deleteFolderOperation:path] fallback:@"ERR_MAILBOX" error:error];
}
- (BOOL)renameFolderPath:(NSString *)path toPath:(NSString *)newPath error:(NSError **)error {
  return [self runVoidOp:[_imap renameFolderOperation:path otherName:newPath] fallback:@"ERR_MAILBOX" error:error];
}
- (BOOL)noopWithError:(NSError **)error {
  return [self runVoidOp:[_imap noopOperation] fallback:@"ERR_IMAP" error:error];
}

#pragma mark - SMTP

- (BOOL)sendMessage:(RNOutgoingMessage *)message error:(NSError **)error {
  if (_smtp == nil) {
    if (error) *error = RNMakeError(@"ERR_SMTP", @"No SMTP transport configured for this account");
    return NO;
  }
  MCOMessageBuilder *builder = [[MCOMessageBuilder alloc] init];
  if (message.from) builder.header.from = RNMCOFromAddress(message.from);
  builder.header.to = RNMCOFromAddresses(message.to);
  builder.header.cc = RNMCOFromAddresses(message.cc);
  builder.header.bcc = RNMCOFromAddresses(message.bcc);
  builder.header.replyTo = RNMCOFromAddresses(message.replyTo);
  builder.header.subject = message.subject;
  if (message.inReplyTo) builder.header.inReplyTo = @[message.inReplyTo];
  if (message.references.count > 0) builder.header.references = message.references;
  [message.customHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
    [builder.header setExtraHeaderValue:v forName:k];
  }];
  if (message.html) builder.htmlBody = message.html;
  if (message.text) builder.textBody = message.text;

  for (RNOutgoingAttachment *att in message.attachments) {
    MCOAttachment *a = nil;
    if (att.data != nil) {
      a = [MCOAttachment attachmentWithData:att.data filename:att.filename];
    } else if (att.path.length > 0) {
      NSString *p = [att.path hasPrefix:@"file://"] ? [[NSURL URLWithString:att.path] path] : att.path;
      a = [MCOAttachment attachmentWithContentsOfFile:p];
      if (att.filename.length > 0) a.filename = att.filename;
    }
    if (a == nil) continue;
    if (att.mimeType.length > 0) a.mimeType = att.mimeType;
    if (att.isInline) {
      a.contentID = att.contentId ?: a.contentID;
      [builder addRelatedAttachment:a];
    } else {
      [builder addAttachment:a];
    }
  }

  __block NSError *opError = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  MCOSMTPSendOperation *op = [_smtp sendOperationWithData:[builder data]];
  [op start:^(NSError *err) {
    opError = err;
    dispatch_semaphore_signal(sem);
  }];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
  if (opError != nil) {
    if (error) *error = RNMapMailCoreError(opError, @"ERR_SMTP");
    return NO;
  }
  return YES;
}

#pragma mark - Mailbox-level

- (RNMessageHeader *)headerFromMessage:(MCOIMAPMessage *)m {
  RNMessageHeader *h = [RNMessageHeader new];
  h.uid = m.uid;
  MCOMessageHeader *mh = m.header;
  h.messageId = mh.messageID;
  h.subject = mh.subject;
  h.from = mh.from ? @[RNAddressFromMCO(mh.from)] : @[];
  h.to = RNAddressesFromMCO(mh.to);
  h.cc = RNAddressesFromMCO(mh.cc);
  h.bcc = RNAddressesFromMCO(mh.bcc);
  h.replyTo = RNAddressesFromMCO(mh.replyTo);
  h.dateMs = RNDateMs(mh.receivedDate ?: mh.date);
  h.flags = RNFlagNames(m.flags);
  h.size = @(m.size);
  h.inReplyTo = mh.inReplyTo.firstObject;
  h.references = mh.references ?: @[];
  // hasAttachments: inspect the fetched body structure, if present.
  BOOL hasAtt = NO;
  NSArray *parts = [m attachments];
  if (parts.count > 0) hasAtt = YES;
  h.hasAttachments = hasAtt;
  return h;
}

- (nullable NSArray<NSNumber *> *)allUidsInFolder:(NSString *)folderPath error:(NSError **)error {
  __block NSError *opError = nil;
  __block NSArray<MCOIMAPMessage *> *messages = nil;
  MCOIndexSet *range = [MCOIndexSet indexSetWithRange:MCORangeMake(1, UINT64_MAX)];
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  MCOIMAPFetchMessagesOperation *op =
    [_imap fetchMessagesByUIDOperation:folderPath
                          requestKind:MCOIMAPMessagesRequestKindUid
                                 uids:range];
  [op start:^(NSError *err, NSArray<MCOIMAPMessage *> *result, MCOIndexSet *vanished) {
    opError = err;
    messages = result;
    dispatch_semaphore_signal(sem);
  }];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
  if (opError != nil) {
    if (error) *error = RNMapMailCoreError(opError, @"ERR_IMAP");
    return nil;
  }
  NSMutableArray<NSNumber *> *uids = [NSMutableArray array];
  for (MCOIMAPMessage *m in messages) [uids addObject:@(m.uid)];
  [uids sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [a compare:b]; }];
  return uids;
}

- (nullable NSArray<RNMessageHeader *> *)fetchHeadersInFolder:(NSString *)folderPath
                                                        uids:(nullable NSArray<NSNumber *> *)uids
                                                       error:(NSError **)error {
  MCOIndexSet *set = uids ? RNIndexSetFromUids(uids)
                          : [MCOIndexSet indexSetWithRange:MCORangeMake(1, UINT64_MAX)];
  MCOIMAPMessagesRequestKind kind = (MCOIMAPMessagesRequestKind)
    (MCOIMAPMessagesRequestKindHeaders | MCOIMAPMessagesRequestKindFlags |
     MCOIMAPMessagesRequestKindStructure | MCOIMAPMessagesRequestKindSize |
     MCOIMAPMessagesRequestKindInternalDate);

  __block NSError *opError = nil;
  __block NSArray<MCOIMAPMessage *> *messages = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  MCOIMAPFetchMessagesOperation *op = [_imap fetchMessagesByUIDOperation:folderPath requestKind:kind uids:set];
  [op start:^(NSError *err, NSArray<MCOIMAPMessage *> *result, MCOIndexSet *vanished) {
    opError = err;
    messages = result;
    dispatch_semaphore_signal(sem);
  }];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
  if (opError != nil) {
    if (error) *error = RNMapMailCoreError(opError, @"ERR_IMAP");
    return nil;
  }
  NSMutableArray<RNMessageHeader *> *out = [NSMutableArray array];
  for (MCOIMAPMessage *m in messages) [out addObject:[self headerFromMessage:m]];
  // Newest first by uid.
  [out sortUsingComparator:^NSComparisonResult(RNMessageHeader *a, RNMessageHeader *b) {
    return a.uid < b.uid ? NSOrderedDescending : (a.uid > b.uid ? NSOrderedAscending : NSOrderedSame);
  }];
  return out;
}

- (nullable RNMessage *)fetchMessageInFolder:(NSString *)folderPath
                                         uid:(uint32_t)uid
                          includeAttachments:(BOOL)includeAttachments
                           maxAttachmentBytes:(int64_t)maxAttachmentBytes
                                    markSeen:(BOOL)markSeen
                                       error:(NSError **)error {
  __block NSError *opError = nil;
  __block NSData *data = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  MCOIMAPFetchContentOperation *op = [_imap fetchMessageByUIDOperation:folderPath uid:uid];
  [op start:^(NSError *err, NSData *result) {
    opError = err;
    data = result;
    dispatch_semaphore_signal(sem);
  }];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
  if (opError != nil) {
    if (error) *error = RNMapMailCoreError(opError, @"ERR_IMAP");
    return nil;
  }
  if (data == nil) {
    if (error) *error = RNMakeError(@"ERR_PARSE", @"Empty message body");
    return nil;
  }

  MCOMessageParser *parser = [MCOMessageParser messageParserWithData:data];
  RNMessage *out = [RNMessage new];
  RNMessageHeader *h = [RNMessageHeader new];
  h.uid = uid;
  MCOMessageHeader *mh = parser.header;
  h.messageId = mh.messageID;
  h.subject = mh.subject;
  h.from = mh.from ? @[RNAddressFromMCO(mh.from)] : @[];
  h.to = RNAddressesFromMCO(mh.to);
  h.cc = RNAddressesFromMCO(mh.cc);
  h.bcc = RNAddressesFromMCO(mh.bcc);
  h.replyTo = RNAddressesFromMCO(mh.replyTo);
  h.dateMs = RNDateMs(mh.date);
  h.flags = @[];
  h.size = @(data.length);
  h.inReplyTo = mh.inReplyTo.firstObject;
  h.references = mh.references ?: @[];
  h.hasAttachments = parser.attachments.count > 0;
  out.header = h;

  out.htmlBody = [parser htmlBodyRendering];
  out.textBody = [parser plainTextBodyRendering];

  NSMutableArray<RNAttachment *> *atts = [NSMutableArray array];
  NSArray<MCOAttachment *> *allAtt = [parser.attachments arrayByAddingObjectsFromArray:(parser.htmlInlineAttachments ?: @[])];
  NSUInteger index = 0;
  for (MCOAttachment *a in allAtt) {
    RNAttachment *r = [RNAttachment new];
    r.partId = a.partID ?: [NSString stringWithFormat:@"%lu", (unsigned long)index];
    r.filename = a.filename;
    r.mimeType = a.mimeType ?: @"application/octet-stream";
    r.contentId = a.contentID;
    r.isInline = a.isInlineAttachment;
    NSData *bytes = a.data;
    r.size = bytes.length;
    if (includeAttachments && bytes != nil &&
        (maxAttachmentBytes <= 0 || (int64_t)bytes.length <= maxAttachmentBytes)) {
      r.data = bytes;
    }
    [atts addObject:r];
    index++;
  }
  out.attachments = atts;

  if (markSeen) {
    NSError *flagErr = nil;
    [self storeFlagsInFolder:folderPath uids:@[@(uid)] flags:@[@"\\Seen"] mode:0 error:&flagErr];
  }
  return out;
}

- (nullable NSData *)fetchAttachmentInFolder:(NSString *)folderPath
                                         uid:(uint32_t)uid
                                      partId:(NSString *)partId
                                       error:(NSError **)error {
  // v1: re-parse the message and return the matching part's bytes. (A future
  // optimization can fetch just the single body part by its IMAP part id.)
  RNMessage *message = [self fetchMessageInFolder:folderPath uid:uid includeAttachments:YES
                               maxAttachmentBytes:0 markSeen:NO error:error];
  if (message == nil) return nil;
  for (RNAttachment *a in message.attachments) {
    if ([a.partId isEqualToString:partId] && a.data != nil) return a.data;
  }
  if (error) *error = RNMakeError(@"ERR_PARSE", @"Attachment part not found");
  return nil;
}

- (nullable NSArray<NSNumber *> *)searchInFolder:(NSString *)folderPath
                                        criteria:(RNSearchCriteria *)c
                                           error:(NSError **)error {
  NSMutableArray<MCOIMAPSearchExpression *> *terms = [NSMutableArray array];
  if (c.text.length) [terms addObject:[MCOIMAPSearchExpression searchContent:c.text]];
  if (c.from.length) [terms addObject:[MCOIMAPSearchExpression searchFrom:c.from]];
  if (c.to.length) [terms addObject:[MCOIMAPSearchExpression searchTo:c.to]];
  if (c.subject.length) [terms addObject:[MCOIMAPSearchExpression searchSubject:c.subject]];
  if (c.body.length) [terms addObject:[MCOIMAPSearchExpression searchBody:c.body]];
  if (c.sinceDateMs) [terms addObject:[MCOIMAPSearchExpression searchSinceReceivedDate:[NSDate dateWithTimeIntervalSince1970:c.sinceDateMs.doubleValue / 1000.0]]];
  if (c.beforeDateMs) [terms addObject:[MCOIMAPSearchExpression searchBeforeReceivedDate:[NSDate dateWithTimeIntervalSince1970:c.beforeDateMs.doubleValue / 1000.0]]];

  MCOIMAPSearchExpression *expr = nil;
  if (terms.count == 0) {
    expr = [MCOIMAPSearchExpression searchAll];
  } else {
    expr = terms[0];
    for (NSUInteger i = 1; i < terms.count; i++) {
      expr = [MCOIMAPSearchExpression searchAnd:expr other:terms[i]];
    }
  }

  __block NSError *opError = nil;
  __block MCOIndexSet *resultSet = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  MCOIMAPSearchOperation *op = [_imap searchExpressionOperation:folderPath expression:expr];
  [op start:^(NSError *err, MCOIndexSet *result) {
    opError = err;
    resultSet = result;
    dispatch_semaphore_signal(sem);
  }];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
  if (opError != nil) {
    if (error) *error = RNMapMailCoreError(opError, @"ERR_IMAP");
    return nil;
  }
  NSMutableArray<NSNumber *> *uids = [NSMutableArray array];
  [resultSet enumerateIndexes:^(uint64_t idx) { [uids addObject:@(idx)]; }];
  // uidRange filter (client-side; MailCore search has no UID-range term here).
  if (c.uidRangeStart || c.uidRangeEnd) {
    uint64_t lo = c.uidRangeStart ? c.uidRangeStart.unsignedLongLongValue : 0;
    uint64_t hi = c.uidRangeEnd ? c.uidRangeEnd.unsignedLongLongValue : UINT64_MAX;
    NSMutableArray<NSNumber *> *filtered = [NSMutableArray array];
    for (NSNumber *u in uids) {
      uint64_t v = u.unsignedLongLongValue;
      if (v >= lo && v <= hi) [filtered addObject:u];
    }
    uids = filtered;
  }
  return uids;
}

- (BOOL)storeFlagsInFolder:(NSString *)folderPath
                      uids:(NSArray<NSNumber *> *)uids
                     flags:(NSArray<NSString *> *)flags
                      mode:(int)mode
                     error:(NSError **)error {
  MCOIMAPStoreFlagsRequestKind kind = MCOIMAPStoreFlagsRequestKindAdd;
  if (mode == 1) kind = MCOIMAPStoreFlagsRequestKindRemove;
  else if (mode == 2) kind = MCOIMAPStoreFlagsRequestKindSet;
  MCOIMAPOperation *op = [_imap storeFlagsOperation:folderPath
                                               uids:RNIndexSetFromUids(uids)
                                               kind:kind
                                              flags:RNFlagMask(flags)];
  return [self runVoidOp:op fallback:@"ERR_IMAP" error:error];
}

- (BOOL)copyMessagesInFolder:(NSString *)folderPath
                        uids:(NSArray<NSNumber *> *)uids
                 destination:(NSString *)destination
                       error:(NSError **)error {
  __block NSError *opError = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  MCOIMAPCopyMessagesOperation *op = [_imap copyMessagesOperation:folderPath
                                                             uids:RNIndexSetFromUids(uids)
                                                        destFolder:destination];
  [op start:^(NSError *err, NSDictionary *uidMapping) {
    opError = err;
    dispatch_semaphore_signal(sem);
  }];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
  if (opError != nil) {
    if (error) *error = RNMapMailCoreError(opError, @"ERR_IMAP");
    return NO;
  }
  return YES;
}

- (BOOL)moveMessagesInFolder:(NSString *)folderPath
                        uids:(NSArray<NSNumber *> *)uids
                 destination:(NSString *)destination
                       error:(NSError **)error {
  // Move = copy to destination, mark source \Deleted, expunge.
  if (![self copyMessagesInFolder:folderPath uids:uids destination:destination error:error]) return NO;
  if (![self storeFlagsInFolder:folderPath uids:uids flags:@[@"\\Deleted"] mode:0 error:error]) return NO;
  return [self runVoidOp:[_imap expungeOperation:folderPath] fallback:@"ERR_IMAP" error:error];
}

- (BOOL)deleteMessagesInFolder:(NSString *)folderPath
                          uids:(NSArray<NSNumber *> *)uids
                       expunge:(BOOL)expunge
                         error:(NSError **)error {
  if (![self storeFlagsInFolder:folderPath uids:uids flags:@[@"\\Deleted"] mode:0 error:error]) return NO;
  if (!expunge) return YES;
  return [self runVoidOp:[_imap expungeOperation:folderPath] fallback:@"ERR_IMAP" error:error];
}

#pragma mark - IDLE

- (BOOL)serverSupportsIdle {
  return [_imap isIdleEnabled];
}

- (BOOL)idleOnceInFolder:(NSString *)folderPath
                lastKnownUid:(uint32_t)lastKnownUid
                      onMail:(void (^)(NSArray<NSNumber *> *uids, uint32_t exists))onMail
                       error:(NSError **)error {
  __block NSError *opError = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  MCOIMAPIdleOperation *op = [_imap idleOperation:folderPath lastKnownUID:lastKnownUid];
  _idleOp = op;
  [op start:^(NSError *err) {
    opError = err;
    dispatch_semaphore_signal(sem);
  }];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
  _idleOp = nil;
  if (opError != nil) {
    if (error) *error = RNMapMailCoreError(opError, @"ERR_IMAP");
    return NO;
  }
  // Woken up: gather the UIDs above lastKnownUid + current EXISTS.
  NSError *statusErr = nil;
  RNFolderStatus *status = [self selectFolderPath:folderPath error:&statusErr];
  uint32_t exists = status ? status.messageCount : 0;
  NSMutableArray<NSNumber *> *newUids = [NSMutableArray array];
  NSArray<NSNumber *> *all = [self allUidsInFolder:folderPath error:nil];
  for (NSNumber *u in all) {
    if (u.unsignedIntValue > lastKnownUid) [newUids addObject:u];
  }
  if (onMail) onMail(newUids, exists);
  return YES;
}

- (void)interruptIdle {
  [_idleOp interruptIdle];
}

- (void)disconnect {
  [self interruptIdle];
  [_imap disconnectOperation];
  _smtp = nil;
}

@end
