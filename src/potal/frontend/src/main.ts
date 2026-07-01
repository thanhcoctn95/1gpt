import { createApp } from "vue";
import { createI18n } from "vue-i18n";
import App from "./App.vue";
import en from "./locales/en";
import vi from "./locales/vi";
import "./assets/style.css";
import "./admin/admin-appshell.css";
import "./assets/landing.css";

function detectLocale(): string {
	const stored = localStorage.getItem("potalLocale");
	if (stored === "vi" || stored === "en") return stored;
	const navLang = (navigator.language || "").toLowerCase();
	if (navLang.startsWith("vi")) return "vi";
	return "vi";
}

const i18n = createI18n({
	legacy: false,
	locale: detectLocale(),
	fallbackLocale: "en",
	messages: { vi, en },
});

const app = createApp(App);
app.use(i18n);
app.mount("#app");
