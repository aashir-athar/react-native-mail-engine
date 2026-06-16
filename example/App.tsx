/**
 * Example consumer for `react-native-mail-engine`.
 *
 * A tiny inbox: connect (app-password or pasted XOAUTH2 token), open INBOX,
 * fetch the 25 newest headers, tap one to load the full parsed message, and
 * toggle IMAP IDLE push.
 *
 * This is a Nitro module — run a dev build, not Expo Go:
 *   cd example && npx expo prebuild --clean && npx expo run:ios  (or run:android)
 *
 * Ships with the repo only, not the npm tarball.
 */

import {
  MailEngine,
  type MailAccount,
  type Mailbox,
  type Message,
  type MessageHeader,
} from 'react-native-mail-engine';
import { useCallback, useRef, useState } from 'react';
import {
  Button,
  FlatList,
  SafeAreaView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';

export default function App() {
  const [user, setUser] = useState('');
  const [secret, setSecret] = useState('');
  const [useOAuth, setUseOAuth] = useState(false);
  const [status, setStatus] = useState('Not connected');
  const [headers, setHeaders] = useState<MessageHeader[]>([]);
  const [open, setOpen] = useState<Message | null>(null);
  const [idling, setIdling] = useState(false);

  const account = useRef<MailAccount | null>(null);
  const inbox = useRef<Mailbox | null>(null);
  const stopIdle = useRef<(() => void) | null>(null);

  const connect = useCallback(async () => {
    try {
      setStatus('Connecting…');
      const acc = await MailEngine.connect({
        imap: { host: 'imap.gmail.com', port: 993, security: 'tls' },
        smtp: { host: 'smtp.gmail.com', port: 465, security: 'tls' },
        auth: useOAuth
          ? { type: 'xoauth2', user, accessToken: secret }
          : { type: 'password', user, password: secret },
      });
      const box = await acc.openMailbox('INBOX');
      const list = await box.fetchHeaders({ limit: 25 });
      account.current = acc;
      inbox.current = box;
      setHeaders(list);
      setStatus(`Connected · ${box.exists} messages, ${box.unseen} unseen`);
    } catch (e) {
      const err = e as { code?: string; message?: string };
      setStatus(`Error ${err.code ?? ''}: ${err.message ?? e}`);
    }
  }, [user, secret, useOAuth]);

  const openMessage = useCallback(async (uid: number) => {
    const box = inbox.current;
    if (!box) return;
    setOpen(await box.fetchMessage(uid, { markSeen: true }));
  }, []);

  const toggleIdle = useCallback(() => {
    const box = inbox.current;
    if (!box) return;
    if (idling) {
      stopIdle.current?.();
      stopIdle.current = null;
      setIdling(false);
      return;
    }
    stopIdle.current = box.idle(
      (event) => setStatus(`📬 new mail: ${event.uids.join(', ')} (exists ${event.exists})`),
      (err) => setStatus(`IDLE error: ${err.message}`)
    );
    setIdling(true);
  }, [idling]);

  return (
    <SafeAreaView style={styles.container}>
      <Text style={styles.title}>react-native-mail-engine</Text>

      {open ? (
        <View style={{ flex: 1 }}>
          <Button title="← Back" onPress={() => setOpen(null)} />
          <Text style={styles.subject}>{open.header.subject ?? '(no subject)'}</Text>
          <Text style={styles.meta}>
            {open.header.from.map((a) => a.email).join(', ')} · {open.attachments.length} attachment(s)
          </Text>
          <Text style={styles.body}>{open.textBody ?? open.htmlBody ?? '(empty body)'}</Text>
        </View>
      ) : (
        <>
          <TextInput style={styles.input} placeholder="email" autoCapitalize="none" value={user} onChangeText={setUser} />
          <TextInput
            style={styles.input}
            placeholder={useOAuth ? 'access token' : 'app password'}
            secureTextEntry
            value={secret}
            onChangeText={setSecret}
          />
          <View style={styles.row}>
            <Text style={styles.meta}>XOAUTH2</Text>
            <Switch value={useOAuth} onValueChange={setUseOAuth} />
            <Button title="Connect" onPress={connect} />
            <Button title={idling ? 'Stop IDLE' : 'IDLE'} onPress={toggleIdle} />
          </View>
          <Text style={styles.status}>{status}</Text>
          <FlatList
            style={{ flex: 1 }}
            data={headers}
            keyExtractor={(h) => String(h.uid)}
            renderItem={({ item }) => (
              <Text style={styles.message} onPress={() => openMessage(item.uid)}>
                {item.flags.includes('\\Seen') ? '  ' : '● '}
                {(item.from[0]?.name ?? item.from[0]?.email ?? '?').padEnd(0)} — {item.subject ?? '(no subject)'}
              </Text>
            )}
          />
        </>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 16, backgroundColor: '#0b0f14' },
  title: { fontSize: 20, fontWeight: '700', color: '#fff', marginBottom: 12 },
  input: { backgroundColor: '#172029', color: '#fff', padding: 10, borderRadius: 8, marginBottom: 8 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 8 },
  status: { color: '#8a94a6', marginBottom: 8 },
  message: { color: '#e6edf3', paddingVertical: 8, borderBottomWidth: 1, borderBottomColor: '#1c2530' },
  subject: { color: '#fff', fontSize: 18, fontWeight: '700', marginTop: 8 },
  meta: { color: '#8a94a6', marginVertical: 4 },
  body: { color: '#e6edf3', marginTop: 8 },
});
