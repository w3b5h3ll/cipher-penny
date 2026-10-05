import '@fontsource-variable/inter';
import '@fontsource-variable/jetbrains-mono';
import '@fontsource-variable/noto-sans-sc';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { session } from './state/session';
import { App } from './ui/App';
import './styles.css';

void session.init();

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
