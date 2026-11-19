import { Head, router } from '@inertiajs/react';
import { Check, Layers, Repeat, Receipt, X } from 'lucide-react';
import { useState } from 'react';
import { ContactAvatar } from '@/components/phamani/contact-avatar';
import { DashboardHeader } from '@/components/phamani/dashboard/dashboard-header';
import { formatCurrency, formatDate } from '@/lib/format';
import { dashboard } from '@/routes';
import {
    accept as acceptInvitation,
    decline as declineInvitation,
} from '@/routes/invitations';
import {
    accept as acceptShare,
    decline as declineShare,
    leave as leaveShare,
} from '@/routes/shares';
import type {
    Account,
    Category,
    PendingInvitation,
    ShareSummary,
} from '@/types/phamani';

interface InboxProps {
    invitations: PendingInvitation[];
    pendingShares: ShareSummary[];
    acceptedShares: ShareSummary[];
    categories: Category[];
    accounts: Account[];
}

const SOURCE_LABEL: Record<ShareSummary['source_type'], string> = {
    transaction: 'Despesa',
    installment: 'Parcelamento',
    recurring: 'Recorrente',
};

const SOURCE_ICON = {
    transaction: Receipt,
    installment: Layers,
    recurring: Repeat,
} as const;

export default function InboxIndex({
    invitations,
    pendingShares,
    acceptedShares,
    categories,
    accounts,
}: InboxProps) {
    const nothing =
        invitations.length === 0 &&
        pendingShares.length === 0 &&
        acceptedShares.length === 0;

    return (
        <>
            <Head title="Pendências" />

            <div className="mx-auto max-w-4xl p-6 md:p-8">
                <DashboardHeader
                    title="Pendências"
                    subtitle="Convites e divisões compartilhadas com você"
                    onBack={() => router.visit(dashboard.url())}
                />

                {nothing && (
                    <p className="rounded-3xl border border-dashed border-[#D4C5A9] p-12 text-center text-[#8B7355]">
                        Nenhuma pendência. Quando alguém te convidar ou dividir
                        uma conta com você, aparece aqui.
                    </p>
                )}

                {invitations.length > 0 && (
                    <Section title="Convites">
                        {invitations.map((inv) => (
                            <InvitationCard key={inv.id} invitation={inv} />
                        ))}
                    </Section>
                )}

                {pendingShares.length > 0 && (
                    <Section title="Divisões para aceitar">
                        {pendingShares.map((share) => (
                            <PendingShareCard
                                key={share.id}
                                share={share}
                                categories={categories}
                                accounts={accounts}
                            />
                        ))}
                    </Section>
                )}

                {acceptedShares.length > 0 && (
                    <Section title="Divisões aceitas">
                        {acceptedShares.map((share) => (
                            <AcceptedShareCard key={share.id} share={share} />
                        ))}
                    </Section>
                )}
            </div>
        </>
    );
}

function Section({
    title,
    children,
}: {
    title: string;
    children: React.ReactNode;
}) {
    return (
        <section className="mb-10">
            <h2 className="mb-4 text-lg font-bold text-[#3D2817]">{title}</h2>
            <div className="space-y-4">{children}</div>
        </section>
    );
}

function InvitationCard({ invitation }: { invitation: PendingInvitation }) {
    const [busy, setBusy] = useState(false);
    const opts = {
        preserveScroll: true,
        onStart: () => setBusy(true),
        onFinish: () => setBusy(false),
    };

    return (
        <div className="flex flex-wrap items-center justify-between gap-4 rounded-3xl border border-[#E8DCC4] bg-white p-5 shadow-sm">
            <div className="flex items-center gap-3">
                <ContactAvatar
                    name={invitation.inviter?.name ?? '?'}
                    avatar={invitation.inviter?.avatar}
                    className="h-11 w-11"
                />
                <div>
                    <p className="font-bold text-[#3D2817]">
                        {invitation.inviter?.name ?? 'Alguém'} quer dividir
                        contas com você
                    </p>
                    <p className="text-sm text-[#8B7355]">
                        {invitation.inviter?.email}
                    </p>
                </div>
            </div>
            <div className="flex gap-2">
                <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                        router.post(
                            declineInvitation.url(invitation.id),
                            {},
                            opts,
                        )
                    }
                    className="rounded-xl border-2 border-[#D4C5A9] px-4 py-2 text-sm font-medium text-[#6B4E3D] hover:bg-[#E8DCC4] disabled:opacity-50"
                >
                    Recusar
                </button>
                <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                        router.post(
                            acceptInvitation.url(invitation.id),
                            {},
                            opts,
                        )
                    }
                    className="flex items-center gap-2 rounded-xl bg-[#3D2817] px-4 py-2 text-sm font-medium text-[#F5EFE6] hover:bg-[#543924] disabled:opacity-50"
                >
                    <Check className="h-4 w-4" /> Aceitar
                </button>
            </div>
        </div>
    );
}

function ShareHeader({ share }: { share: ShareSummary }) {
    const Icon = SOURCE_ICON[share.source_type];

    return (
        <div className="flex flex-wrap items-start justify-between gap-4">
            <div className="flex items-start gap-3">
                <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-[#E8DCC4] text-[#6B4E3D]">
                    <Icon className="h-5 w-5" />
                </div>
                <div>
                    <p className="font-bold text-[#3D2817]">{share.name}</p>
                    <p className="flex flex-wrap items-center gap-1 text-sm text-[#8B7355]">
                        <ContactAvatar
                            name={share.owner.name}
                            avatar={share.owner.avatar}
                            className="h-5 w-5 text-[9px]"
                        />
                        {SOURCE_LABEL[share.source_type]} de {share.owner.name}
                        {share.date && ` · ${formatDate(share.date)}`}
                        {share.items > 1 && ` · ${share.items} lançamentos`}
                    </p>
                    <p className="text-xs text-[#8B7355]">
                        Pago por {share.paid_by ?? '—'}
                    </p>
                </div>
            </div>
            <div className="text-right">
                <p className="text-xs font-bold tracking-wider text-[#8B7355] uppercase">
                    Sua parte
                </p>
                <p className="text-2xl font-bold text-[#3D2817]">
                    {formatCurrency(share.my_amount)}
                </p>
                {share.total != null && (
                    <p className="text-xs text-[#8B7355]">
                        de {formatCurrency(share.total)}
                    </p>
                )}
            </div>
        </div>
    );
}

function PendingShareCard({
    share,
    categories,
    accounts,
}: {
    share: ShareSummary;
    categories: Category[];
    accounts: Account[];
}) {
    const expenseCategories = categories.filter((c) => c.type !== 'income');
    const [categoryId, setCategoryId] = useState(
        share.category_id ?? expenseCategories[0]?.id ?? '',
    );
    const [accountId, setAccountId] = useState(share.account_id ?? '');
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const opts = {
        preserveScroll: true,
        onStart: () => {
            setBusy(true);
            setError(null);
        },
        onFinish: () => setBusy(false),
        onError: (errors: Record<string, string>) =>
            setError(Object.values(errors)[0] ?? 'Não foi possível concluir.'),
    };

    return (
        <div className="rounded-3xl border border-[#E8DCC4] bg-white p-5 shadow-sm">
            <ShareHeader share={share} />

            <div className="mt-5 grid gap-3 border-t border-[#E8DCC4] pt-5 md:grid-cols-2">
                <div>
                    <label
                        htmlFor={`cat-${share.id}`}
                        className="mb-1 ml-1 block text-xs text-[#8B7355]"
                    >
                        Categoria no seu Phamani
                    </label>
                    <select
                        id={`cat-${share.id}`}
                        value={categoryId}
                        onChange={(e) => setCategoryId(e.target.value)}
                        className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-3 py-2 text-[#3D2817]"
                    >
                        {expenseCategories.map((c) => (
                            <option key={c.id} value={c.id}>
                                {c.name}
                            </option>
                        ))}
                    </select>
                </div>
                <div>
                    <label
                        htmlFor={`acc-${share.id}`}
                        className="mb-1 ml-1 block text-xs text-[#8B7355]"
                    >
                        {share.you_paid
                            ? 'Você pagou: de qual conta/cartão saiu?'
                            : 'Quando você pagar, sai de (opcional)'}
                    </label>
                    <select
                        id={`acc-${share.id}`}
                        value={accountId}
                        onChange={(e) => setAccountId(e.target.value)}
                        className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-3 py-2 text-[#3D2817]"
                    >
                        <option value="">Nenhuma</option>
                        {accounts.map((a) => (
                            <option key={a.id} value={a.id}>
                                {a.name}
                            </option>
                        ))}
                    </select>
                </div>
            </div>

            {error && <p className="mt-2 text-xs text-[#D4183D]">{error}</p>}

            <p className="mt-3 text-xs text-[#8B7355]">
                {share.source_type === 'transaction'
                    ? 'Ao aceitar, sua parte entra nas suas transações.'
                    : 'Ao aceitar, vale para a série inteira: os próximos lançamentos chegam sozinhos.'}{' '}
                Só quem criou pode alterar os valores.
            </p>

            <div className="mt-4 flex justify-end gap-2">
                <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                        router.post(declineShare.url(share.id), {}, opts)
                    }
                    className="flex items-center gap-2 rounded-xl border-2 border-[#D4C5A9] px-4 py-2 text-sm font-medium text-[#6B4E3D] hover:bg-[#E8DCC4] disabled:opacity-50"
                >
                    <X className="h-4 w-4" /> Recusar
                </button>
                <button
                    type="button"
                    disabled={busy || !categoryId}
                    onClick={() =>
                        router.post(
                            acceptShare.url(share.id),
                            {
                                category_id: categoryId,
                                account_id: accountId || null,
                            },
                            opts,
                        )
                    }
                    className="flex items-center gap-2 rounded-xl bg-[#3D2817] px-4 py-2 text-sm font-medium text-[#F5EFE6] hover:bg-[#543924] disabled:opacity-50"
                >
                    <Check className="h-4 w-4" /> Aceitar
                </button>
            </div>
        </div>
    );
}

function AcceptedShareCard({ share }: { share: ShareSummary }) {
    const [confirming, setConfirming] = useState(false);

    return (
        <div className="rounded-3xl border border-[#E8DCC4] bg-[#FBF7F1] p-5">
            <ShareHeader share={share} />
            <div className="mt-4 flex justify-end gap-2">
                {confirming ? (
                    <>
                        <button
                            type="button"
                            onClick={() => setConfirming(false)}
                            className="rounded-xl border-2 border-[#D4C5A9] px-4 py-2 text-sm font-medium text-[#6B4E3D] hover:bg-[#E8DCC4]"
                        >
                            Cancelar
                        </button>
                        <button
                            type="button"
                            onClick={() =>
                                router.post(
                                    leaveShare.url(share.id),
                                    {},
                                    { preserveScroll: true },
                                )
                            }
                            className="rounded-xl bg-[#A65D57] px-4 py-2 text-sm font-medium text-white hover:bg-[#8B4543]"
                        >
                            Sair e remover minha parte
                        </button>
                    </>
                ) : (
                    <button
                        type="button"
                        onClick={() => setConfirming(true)}
                        className="rounded-xl border-2 border-[#D4C5A9] px-4 py-2 text-sm font-medium text-[#6B4E3D] hover:bg-[#E8DCC4]"
                    >
                        Sair da divisão
                    </button>
                )}
            </div>
        </div>
    );
}
