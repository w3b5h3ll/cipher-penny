import { useCallback, useEffect, useRef, useState } from 'react';

// Minimal typing for the Web Speech API; not all TS DOM libs ship it.
interface RecognitionResultEvent {
  resultIndex: number;
  results: ArrayLike<{ isFinal: boolean; 0: { transcript: string } }>;
}
interface Recognition {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  start(): void;
  stop(): void;
  abort(): void;
  onresult: ((e: RecognitionResultEvent) => void) | null;
  onerror: ((e: { error: string }) => void) | null;
  onend: (() => void) | null;
}
type RecognitionCtor = new () => Recognition;

function getRecognitionCtor(): RecognitionCtor | undefined {
  if (typeof window === 'undefined') return undefined;
  const w = window as unknown as { SpeechRecognition?: RecognitionCtor; webkitSpeechRecognition?: RecognitionCtor };
  return w.SpeechRecognition ?? w.webkitSpeechRecognition;
}

const ERROR_MESSAGES: Record<string, string> = {
  'not-allowed': '没有麦克风权限，请在浏览器设置中允许',
  'service-not-allowed': '浏览器不允许使用语音识别服务',
  network: '语音识别服务不可用（Chrome 的语音识别需要访问 Google 服务）',
  'no-speech': '没有听到声音，请再试一次',
  'audio-capture': '找不到麦克风',
};

/** F-QA-8: dictation via the browser's speech service. */
export function useSpeech(onFinal: (text: string) => void) {
  const supported = getRecognitionCtor() !== undefined;
  const [listening, setListening] = useState(false);
  const [interim, setInterim] = useState('');
  const [error, setError] = useState<string | null>(null);
  const recRef = useRef<Recognition | null>(null);
  const onFinalRef = useRef(onFinal);

  useEffect(() => {
    onFinalRef.current = onFinal;
  }, [onFinal]);

  useEffect(() => () => recRef.current?.abort(), []);

  const start = useCallback(() => {
    const Ctor = getRecognitionCtor();
    if (!Ctor) return;
    const rec = new Ctor();
    rec.lang = 'zh-CN';
    rec.continuous = false;
    rec.interimResults = true;
    rec.onresult = (e) => {
      let text = '';
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const r = e.results[i]!;
        if (r.isFinal) onFinalRef.current(r[0].transcript);
        else text += r[0].transcript;
      }
      setInterim(text);
    };
    rec.onerror = (e) => setError(ERROR_MESSAGES[e.error] ?? `语音识别出错：${e.error}`);
    rec.onend = () => {
      setListening(false);
      setInterim('');
      recRef.current = null;
    };
    recRef.current = rec;
    setError(null);
    setListening(true);
    rec.start();
  }, []);

  const stop = useCallback(() => recRef.current?.stop(), []);

  return { supported, listening, interim, error, start, stop };
}
