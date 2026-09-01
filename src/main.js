import { createApp } from 'vue'
import './theme.css'
import App from './App.vue'
import AdminView from './views/AdminView.vue'

const isAdmin = window.location.pathname.replace(/\/+$/, '') === '/admin'

createApp(isAdmin ? AdminView : App).mount('#app')
