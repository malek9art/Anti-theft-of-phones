import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter, HashRouter } from 'react-router-dom'
import App from './App'
import { AuthProvider } from './contexts/AuthContext'
import { PwaInstallButton } from './components/PwaInstallButton'
import './styles/global.css'

// GitHub Pages cannot rewrite deep BrowserRouter URLs. The Pages build opts into hash URLs;
// local/custom hosting can keep clean BrowserRouter paths by leaving this unset.
const Router = import.meta.env.VITE_ROUTER_MODE === 'hash' ? HashRouter : BrowserRouter

if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    void navigator.serviceWorker.register(`${import.meta.env.BASE_URL}sw.js`, { scope: import.meta.env.BASE_URL })
      .catch((error: unknown) => console.warn('pwa-service-worker-registration-failed', error))
  })
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Router>
      <AuthProvider><App /></AuthProvider>
      <PwaInstallButton />
    </Router>
  </StrictMode>,
)
