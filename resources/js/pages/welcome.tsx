import { Head } from '@inertiajs/react';
import { BarChart3, Layers, Repeat, ShieldAlert, Wallet } from 'lucide-react';
import { motion } from 'motion/react';
import { redirect as googleRedirect } from '@/routes/auth/google';

export default function Welcome({ error }: { error?: string | null }) {
    return (
        <>
            <Head title="Entrar" />

            <div className="flex min-h-screen items-center justify-center p-6">
                <motion.div
                    initial={{ opacity: 0, y: 16 }}
                    animate={{ opacity: 1, y: 0 }}
                    className="w-full max-w-md rounded-[2rem] border border-[#E8DCC4] bg-[#FBF7F1] p-10 shadow-[0_12px_40px_rgba(61,40,23,0.12)]"
                >
                    <div className="mb-8 flex items-center gap-4">
                        <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-[#6B4F3A] text-[#F5EFE6] shadow-lg">
                            <Wallet className="h-7 w-7" />
                        </div>
                        <div>
                            <h1 className="text-3xl font-bold text-[#3D2817]">
                                Phamani
                            </h1>
                            <p className="text-sm text-[#8B7355]">
                                Gestão Financeira Pessoal
                            </p>
                        </div>
                    </div>

                    <ul className="mb-10 space-y-3 text-sm text-[#6B4F3A]">
                        <li className="flex items-center gap-3">
                            <BarChart3 className="h-4 w-4" /> Fluxo de caixa e
                            despesas por categoria
                        </li>
                        <li className="flex items-center gap-3">
                            <Layers className="h-4 w-4" /> Compras parceladas
                            com linha do tempo
                        </li>
                        <li className="flex items-center gap-3">
                            <Repeat className="h-4 w-4" /> Lançamentos
                            recorrentes
                        </li>
                    </ul>

                    {error && (
                        <div
                            role="alert"
                            className="mb-6 flex items-start gap-3 rounded-xl border border-l-[6px] border-[#E8C4C0] border-l-[#A65D57] bg-[#FFF5F5] px-4 py-3 text-sm text-[#8B4543]"
                        >
                            <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0" />
                            <span>{error}</span>
                        </div>
                    )}

                    {/* Navegação completa (não-Inertia): o Google precisa de um redirect real do navegador. */}
                    <a
                        href={googleRedirect.url()}
                        className="flex w-full items-center justify-center gap-3 rounded-xl border-2 border-[#E8DCC4] bg-white px-6 py-4 font-medium text-[#3D2817] shadow-sm transition-colors hover:border-[#6B4F3A] hover:bg-[#F5EFE6]"
                    >
                        <GoogleIcon />
                        Entrar com Google
                    </a>

                    <p className="mt-6 text-center text-xs text-[#8B7355]">
                        Sem senha: sua conta Google é sua conta no Phamani.
                    </p>
                </motion.div>
            </div>
        </>
    );
}

function GoogleIcon() {
    return (
        <svg className="h-5 w-5" viewBox="0 0 48 48" aria-hidden="true">
            <path
                fill="#FFC107"
                d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z"
            />
            <path
                fill="#FF3D00"
                d="m6.3 14.7 6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z"
            />
            <path
                fill="#4CAF50"
                d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z"
            />
            <path
                fill="#1976D2"
                d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z"
            />
        </svg>
    );
}
