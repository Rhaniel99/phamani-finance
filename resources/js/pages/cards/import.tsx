import { Head, Link, router, usePoll } from '@inertiajs/react';
import {
    AlertTriangle,
    Check,
    ChevronDown,
    CircleCheck,
    Link2,
    Loader2,
    ScanLine,
    Sparkles,
    Trash2,
} from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import { CategoryIcon } from '@/components/phamani/category-icon';
import { DashboardHeader } from '@/components/phamani/dashboard/dashboard-header';
import { TagInput } from '@/components/phamani/tag-input';
import { Button } from '@/components/phamani/ui/button';
import { useContacts } from '@/hooks/use-contacts';
import { formatCurrency, formatDate, formatMonth } from '@/lib/format';
import { cn } from '@/lib/utils';
import { show as cardShow } from '@/routes/cards';
import {
    accept,
    destroy as discardImport,
    show as importShow,
} from '@/routes/imports';
import type {
    Category,
    ImportExisting,
    ImportLine,
    ImportReview,
    StatementImportState,
} from '@/types/phamani';

interface ImportPageProps {
    card: {
        id: string;
        name: string;
        closing_day: number | null;
        due_day: number | null;
    };
    import: StatementImportState;
    review: ImportReview | null;
    categories: Category[];
}

type Split = '' | 'half' | 'theirs';

interface RowState {
    launch: boolean;
    name: string;
    category_id: string;
    tags: string[];
    split: Split;
    contact: string;
    amount: number;
    touched: boolean;
}

type Tab = 'new' | 'matched' | 'ignored';

const inputClass =
    'w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-3 py-2 text-sm text-[#3D2817] focus:border-[#6B4E3D] focus:outline-none';

const KIND_LABEL: Record<string, string> = {
    balance: 'Saldo anterior: não é compra.',
    payment: 'Pagamento da fatura: não é compra.',
    refunded: 'Estorno que anula uma compra igual: os dois ficam de fora.',
    deducted: 'Estorno parcial: já abatido da compra da mesma loja.',
};

const CONFIDENCE_LABEL = {
    exact: 'mesmo valor e data',
    amount: 'mesmo valor, outra data',
    combined: 'soma de várias linhas',
} as const;

const isLaunchable = (line: ImportLine) =>
    line.kind === 'purchase' || line.kind === 'refund';

function defaultRow(line: ImportLine): RowState {
    return {
        launch: isLaunchable(line) && line.match === null,
        name: line.suggestion.name,
        category_id: line.suggestion.category_id ?? '',
        tags: line.suggestion.tags,
        split: '',
        contact: '',
        amount: Math.abs(line.net),
        touched: false,
    };
}

/**
 * Importar extrato: acompanha o OCR (porcentagem) e, quando termina, a revisão:
 * novas (aceitar/recusar, renomear, categorizar, tags, divisão), já cadastradas e ignoradas,
 * com a lista do que já está na fatura do Phamani ao lado.
 */
export default function ImportPage({
    card,
    import: imp,
    review,
    categories,
}: ImportPageProps) {
    const running = imp.status === 'queued' || imp.status === 'processing';

    const { stop } = usePoll(
        1000,
        { only: ['import'] },
        { autoStart: running },
    );

    useEffect(() => {
        if (running) return;
        stop();
        if (imp.status === 'ready' && review === null) {
            router.reload({ only: ['review'] });
        }
    }, [running, imp.status, review, stop]);

    return (
        <>
            <Head title={`Importar extrato · ${card.name}`} />

            <div className="p-6 md:p-8">
                <DashboardHeader
                    title="Importar extrato"
                    subtitle={
                        imp.statement_date
                            ? `${card.name} · extrato de ${formatDate(imp.statement_date)}`
                            : card.name
                    }
                    onBack={() => router.visit(cardShow.url(card.id))}
                    actions={
                        imp.status !== 'done' && (
                            <Button
                                variant="secondary"
                                className="h-12"
                                onClick={() =>
                                    router.delete(discardImport.url(imp.id))
                                }
                            >
                                <Trash2 className="h-5 w-5 md:mr-2" />
                                <span className="hidden md:inline">
                                    Descartar
                                </span>
                            </Button>
                        )
                    }
                />

                {running && <Processing imp={imp} />}

                {imp.status === 'failed' && (
                    <div className="mx-auto max-w-xl rounded-3xl border border-[#E8DCC4] bg-[#FBF7F1] p-8 text-center">
                        <AlertTriangle className="mx-auto mb-3 h-10 w-10 text-[#A65D57]" />
                        <p className="mb-2 text-lg font-bold text-[#3D2817]">
                            Não consegui ler o extrato
                        </p>
                        <p className="mb-6 text-sm text-[#6B4E3D]">
                            {imp.error}
                        </p>
                        <Link
                            href={cardShow.url(card.id)}
                            className="font-bold text-[#3D2817] underline"
                        >
                            Voltar ao cartão
                        </Link>
                    </div>
                )}

                {imp.status === 'done' && (
                    <div className="mx-auto max-w-xl rounded-3xl border border-[#E8DCC4] bg-[#FBF7F1] p-8 text-center">
                        <CircleCheck className="mx-auto mb-3 h-10 w-10 text-[#1F5428]" />
                        <p className="mb-6 text-lg font-bold text-[#3D2817]">
                            Importação concluída: {imp.created_count}{' '}
                            {imp.created_count === 1
                                ? 'compra lançada'
                                : 'compras lançadas'}
                            .
                        </p>
                        <Link
                            href={cardShow.url(card.id)}
                            className="font-bold text-[#3D2817] underline"
                        >
                            Ver o cartão
                        </Link>
                    </div>
                )}

                {imp.status === 'ready' && review && (
                    <Review
                        importId={imp.id}
                        review={review}
                        categories={categories}
                    />
                )}
            </div>
        </>
    );
}

function Processing({ imp }: { imp: StatementImportState }) {
    return (
        <div className="mx-auto max-w-xl rounded-3xl border border-[#E8DCC4] bg-[#FBF7F1] p-8">
            <div className="mb-4 flex items-center gap-3">
                <ScanLine className="h-8 w-8 animate-pulse text-[#6B4E3D]" />
                <div>
                    <p className="text-lg font-bold text-[#3D2817]">
                        Lendo o extrato…
                    </p>
                    <p className="text-sm text-[#8B7355]">
                        {imp.stage ?? 'Na fila'}
                    </p>
                </div>
                <span className="ml-auto text-2xl font-bold text-[#3D2817]">
                    {imp.progress}%
                </span>
            </div>
            <div
                className="h-3 overflow-hidden rounded-full bg-[#E8DCC4]"
                role="progressbar"
                aria-valuenow={imp.progress}
                aria-valuemin={0}
                aria-valuemax={100}
            >
                <div
                    className="h-full rounded-full bg-[#3D2817] transition-all duration-500"
                    style={{ width: `${imp.progress}%` }}
                />
            </div>
            <p className="mt-4 text-xs text-[#8B7355]">
                O OCR roda no servidor, linha por linha. Pode sair desta tela: a
                leitura continua e a revisão fica esperando por você.
            </p>
        </div>
    );
}

function Review({
    importId,
    review,
    categories,
}: {
    importId: string;
    review: ImportReview;
    categories: Category[];
}) {
    const contacts = useContacts();
    const [rows, setRows] = useState<Record<number, RowState>>(() =>
        Object.fromEntries(review.lines.map((l) => [l.index, defaultRow(l)])),
    );
    const [tab, setTab] = useState<Tab>('new');
    const [open, setOpen] = useState<number | null>(null);
    const [remember, setRemember] = useState(true);
    const [bulkCategory, setBulkCategory] = useState('');
    const [errors, setErrors] = useState<Record<number, string>>({});
    const [processing, setProcessing] = useState(false);

    // Trocou a fatura: as ligações mudam; mantém o que você já mexeu.
    useEffect(() => {
        setRows((current) =>
            Object.fromEntries(
                review.lines.map((l) => {
                    const row = current[l.index];
                    return [l.index, row?.touched ? row : defaultRow(l)];
                }),
            ),
        );
    }, [review]);

    const existingById = useMemo(
        () => new Map(review.existing.map((e) => [e.id, e])),
        [review.existing],
    );

    const groups = useMemo(() => {
        const launchable = review.lines.filter(isLaunchable);
        return {
            new: launchable.filter((l) => l.match === null),
            matched: launchable.filter((l) => l.match !== null),
            ignored: review.lines.filter((l) => !isLaunchable(l)),
        };
    }, [review.lines]);

    function update(index: number, patch: Partial<RowState>) {
        setRows((current) => ({
            ...current,
            [index]: { ...current[index], ...patch, touched: true },
        }));
        setErrors((e) => {
            if (!(index in e)) return e;
            const next = { ...e };
            delete next[index];
            return next;
        });
    }

    const launched = review.lines.filter(
        (l) => isLaunchable(l) && rows[l.index]?.launch,
    );

    const launchTotal = launched.reduce(
        (sum, l) =>
            sum + (l.kind === 'refund' ? -1 : 1) * (rows[l.index]?.amount ?? 0),
        0,
    );

    // Já cadastradas que ficaram de fora do lançamento: marcadas como conferidas.
    const reconcile = useMemo(() => {
        const ids = new Set<string>();
        for (const line of groups.matched) {
            if (!rows[line.index]?.launch) {
                line.match?.ids.forEach((id) => ids.add(id));
            }
        }
        return [...ids];
    }, [groups.matched, rows]);

    const statementTotal = review.sections.reduce(
        (sum, s) => sum + (s.total ?? s.sum),
        0,
    );
    const invoiceNow = review.invoice?.total ?? 0;

    function categoriesFor(line: ImportLine) {
        const type = line.kind === 'refund' ? 'income' : 'expense';
        return categories.filter((c) => c.type === type || c.type === 'both');
    }

    function applyBulkCategory(id: string) {
        setBulkCategory(id);
        if (!id) return;
        const category = categories.find((c) => c.id === id);
        setRows((current) => {
            const next = { ...current };
            for (const line of launched) {
                const row = next[line.index];
                const type = line.kind === 'refund' ? 'income' : 'expense';
                if (
                    row &&
                    !row.category_id &&
                    category &&
                    (category.type === type || category.type === 'both')
                ) {
                    next[line.index] = {
                        ...row,
                        category_id: id,
                        touched: true,
                    };
                }
            }
            return next;
        });
    }

    function changeReference(value: string) {
        router.get(
            importShow.url(importId),
            { ref: value },
            {
                only: ['review'],
                preserveState: true,
                preserveScroll: true,
                replace: true,
            },
        );
    }

    function submit() {
        const missing: Record<number, string> = {};
        for (const line of launched) {
            const row = rows[line.index];
            if (!row.category_id) missing[line.index] = 'Escolha a categoria.';
            if (!row.name.trim()) missing[line.index] = 'Dê um nome.';
            if (row.split && !row.contact)
                missing[line.index] = 'Escolha com quem dividir.';
        }
        if (Object.keys(missing).length > 0) {
            setErrors(missing);
            setTab(
                groups.new.some((l) => l.index in missing) ? 'new' : 'matched',
            );
            return;
        }

        const order = launched.map((l) => l.index);

        router.post(
            accept.url(importId),
            {
                reference: review.reference,
                remember,
                reconcile,
                lines: launched.map((l) => {
                    const row = rows[l.index];
                    return {
                        index: l.index,
                        name: row.name.trim(),
                        amount: row.amount,
                        type: l.kind === 'refund' ? 'income' : 'expense',
                        date: l.launch_date,
                        category_id: row.category_id,
                        tags: row.tags,
                        split: row.split || null,
                        split_contact_id: row.split ? row.contact : null,
                    };
                }),
            },
            {
                preserveScroll: true,
                onStart: () => setProcessing(true),
                onFinish: () => setProcessing(false),
                onError: (e) => {
                    const mapped: Record<number, string> = {};
                    for (const [key, message] of Object.entries(e)) {
                        const m = key.match(/^lines\.(\d+)\./);
                        if (m) mapped[order[Number(m[1])]] = message;
                    }
                    setErrors(mapped);
                },
            },
        );
    }

    const visible = groups[tab];
    const firstError = Object.values(errors)[0];

    return (
        <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_380px]">
            <div className="min-w-0 space-y-4">
                {/* Fatura e conferência dos totais */}
                <div className="rounded-3xl border border-[#E8DCC4] bg-[#FBF7F1] p-5">
                    <p className="mb-2 text-xs font-bold tracking-wider text-[#8B7355] uppercase">
                        Lançar na fatura de
                    </p>
                    <div className="mb-4 flex flex-wrap gap-2">
                        {review.references.map((ref) => (
                            <button
                                key={ref.value}
                                type="button"
                                onClick={() => changeReference(ref.value)}
                                className={cn(
                                    'flex flex-col items-start rounded-2xl border px-4 py-2 text-left transition-all',
                                    review.reference === ref.value
                                        ? 'border-[#3D2817] bg-[#3D2817] text-[#F5EFE6]'
                                        : 'border-[#E8DCC4] bg-white text-[#3D2817] hover:border-[#6B4F3A]',
                                )}
                            >
                                <span className="text-sm font-bold capitalize">
                                    {formatMonth(ref.value)}
                                </span>
                                <span className="text-xs opacity-75">
                                    fecha {formatDate(ref.closing).slice(0, 5)}{' '}
                                    ·{' '}
                                    {ref.total != null
                                        ? formatCurrency(ref.total)
                                        : 'vazia'}
                                </span>
                            </button>
                        ))}
                    </div>

                    <div className="flex flex-wrap gap-2">
                        {review.sections.map((s, i) =>
                            s.total === null && s.sum === 0 ? null : (
                                <span
                                    key={i}
                                    className={cn(
                                        'inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-bold',
                                        s.ok
                                            ? 'bg-[#E3F9E5] text-[#1F5428]'
                                            : 'bg-[#FCE7E7] text-[#A65D57]',
                                    )}
                                    title={s.label}
                                >
                                    {s.ok ? (
                                        <Check className="h-3.5 w-3.5" />
                                    ) : (
                                        <AlertTriangle className="h-3.5 w-3.5" />
                                    )}
                                    {s.last4 ? `Final ${s.last4}` : 'Extrato'} ·{' '}
                                    {s.ok
                                        ? `${formatCurrency(s.total ?? s.sum)} confere`
                                        : `soma ${formatCurrency(s.sum)} ≠ total ${formatCurrency(s.total ?? 0)} (faltam ${formatCurrency(s.diff ?? 0)})`}
                                </span>
                            ),
                        )}
                    </div>
                    {review.sections.some((s) => !s.ok) && (
                        <p className="mt-2 text-xs text-[#A65D57]">
                            A soma das linhas lidas não bate com o total do
                            banco: alguma linha foi lida errada ou ficou de
                            fora. Confira os valores marcados.
                        </p>
                    )}
                </div>

                {/* Abas */}
                <div className="flex flex-wrap items-center gap-2">
                    {(
                        [
                            ['new', 'Novas', groups.new.length],
                            [
                                'matched',
                                'Já cadastradas',
                                groups.matched.length,
                            ],
                            ['ignored', 'Ignoradas', groups.ignored.length],
                        ] as const
                    ).map(([key, label, count]) => (
                        <button
                            key={key}
                            type="button"
                            onClick={() => setTab(key)}
                            className={cn(
                                'rounded-full px-4 py-2 text-sm font-bold transition-colors',
                                tab === key
                                    ? 'bg-[#3D2817] text-[#F5EFE6]'
                                    : 'bg-[#E8DCC4] text-[#6B4E3D] hover:bg-[#D4C5A9]',
                            )}
                        >
                            {label} ({count})
                        </button>
                    ))}

                    {tab === 'new' && (
                        <select
                            value={bulkCategory}
                            onChange={(e) => applyBulkCategory(e.target.value)}
                            className="ml-auto rounded-xl border-2 border-[#E8DCC4] bg-white px-3 py-2 text-sm text-[#3D2817]"
                            aria-label="Categoria para as marcadas sem categoria"
                        >
                            <option value="">
                                Categoria p/ marcadas sem categoria…
                            </option>
                            {categories.map((c) => (
                                <option key={c.id} value={c.id}>
                                    {c.name}
                                </option>
                            ))}
                        </select>
                    )}
                </div>

                {visible.length === 0 && (
                    <p className="rounded-2xl border border-dashed border-[#D4C5A9] p-8 text-center text-[#8B7355]">
                        {tab === 'new'
                            ? 'Nada novo: tudo do extrato já está cadastrado.'
                            : tab === 'matched'
                              ? 'Nenhuma linha bateu com o que já está cadastrado.'
                              : 'Nada ignorado.'}
                    </p>
                )}

                <ul className="space-y-2">
                    {visible.map((line) =>
                        tab === 'ignored' ? (
                            <IgnoredRow
                                key={line.index}
                                line={line}
                                pair={review.lines.find(
                                    (l) => l.index === line.pair,
                                )}
                            />
                        ) : (
                            <LineRow
                                key={line.index}
                                line={line}
                                row={rows[line.index]}
                                error={errors[line.index]}
                                open={open === line.index}
                                onToggleOpen={() =>
                                    setOpen(
                                        open === line.index ? null : line.index,
                                    )
                                }
                                onChange={(patch) => update(line.index, patch)}
                                categories={categoriesFor(line)}
                                contacts={contacts}
                                matched={
                                    line.match?.ids
                                        .map((id) => existingById.get(id))
                                        .filter(
                                            (e): e is ImportExisting => !!e,
                                        ) ?? []
                                }
                            />
                        ),
                    )}
                </ul>
            </div>

            {/* Lateral: o que já está no Phamani + resumo */}
            <aside className="space-y-4 lg:sticky lg:top-6 lg:self-start">
                <div className="rounded-3xl border-2 border-[#3D2817] bg-[#E8DCC4] p-5">
                    <SummaryLine
                        label="Total do extrato"
                        value={formatCurrency(statementTotal)}
                    />
                    <SummaryLine
                        label="Fatura no Phamani hoje"
                        value={formatCurrency(invoiceNow)}
                    />
                    <SummaryLine
                        label={`Vai lançar (${launched.length})`}
                        value={formatCurrency(launchTotal)}
                    />
                    <div className="my-3 border-t border-[#D4C5A9]" />
                    <SummaryLine
                        label="Fatura depois"
                        value={formatCurrency(invoiceNow + launchTotal)}
                        strong
                    />
                    {reconcile.length > 0 && (
                        <p className="mt-2 text-xs text-[#6B4E3D]">
                            {reconcile.length} já cadastrada
                            {reconcile.length === 1 ? '' : 's'} será
                            {reconcile.length === 1 ? '' : 'ão'} marcada
                            {reconcile.length === 1 ? '' : 's'} como conferida
                            {reconcile.length === 1 ? '' : 's'}.
                        </p>
                    )}

                    <label className="mt-4 flex items-start gap-2 text-xs text-[#6B4E3D]">
                        <input
                            type="checkbox"
                            checked={remember}
                            onChange={(e) => setRemember(e.target.checked)}
                            className="mt-0.5"
                        />
                        Lembrar nome, categoria e tags de cada loja na próxima
                        importação
                    </label>

                    {firstError && (
                        <p className="mt-3 text-sm text-[#A65D57]">
                            {firstError}
                        </p>
                    )}

                    <Button
                        className="mt-4 h-12 w-full"
                        onClick={submit}
                        disabled={
                            processing ||
                            (launched.length === 0 && reconcile.length === 0)
                        }
                    >
                        {processing && (
                            <Loader2 className="mr-2 h-5 w-5 animate-spin" />
                        )}
                        {launched.length > 0
                            ? `Lançar ${launched.length} ${launched.length === 1 ? 'compra' : 'compras'}`
                            : 'Só marcar como conferidas'}
                    </Button>
                </div>

                <ExistingPanel review={review} />
            </aside>
        </div>
    );
}

function SummaryLine({
    label,
    value,
    strong = false,
}: {
    label: string;
    value: string;
    strong?: boolean;
}) {
    return (
        <div className="flex items-baseline justify-between gap-3 py-0.5">
            <span className="text-sm text-[#6B4E3D]">{label}</span>
            <span
                className={cn(
                    'font-bold text-[#3D2817]',
                    strong ? 'text-xl' : 'text-sm',
                )}
            >
                {value}
            </span>
        </div>
    );
}

function LineRow({
    line,
    row,
    error,
    open,
    onToggleOpen,
    onChange,
    categories,
    contacts,
    matched,
}: {
    line: ImportLine;
    row: RowState;
    error?: string;
    open: boolean;
    onToggleOpen: () => void;
    onChange: (patch: Partial<RowState>) => void;
    categories: Category[];
    contacts: { id: string; name: string }[];
    matched: ImportExisting[];
}) {
    if (!row) return null;
    const credit = line.kind === 'refund';
    const dim = !row.launch;

    return (
        <li
            className={cn(
                'rounded-2xl border bg-white p-3 transition-colors',
                error ? 'border-[#A65D57]' : 'border-[#E8DCC4]',
            )}
        >
            <div className="flex flex-wrap items-center gap-3 md:flex-nowrap">
                <input
                    type="checkbox"
                    checked={row.launch}
                    onChange={(e) => onChange({ launch: e.target.checked })}
                    className="h-5 w-5 shrink-0 accent-[#3D2817]"
                    aria-label={`Lançar ${line.description}`}
                />
                <span
                    className={cn(
                        'w-12 shrink-0 text-sm font-bold',
                        line.date_ok ? 'text-[#6B4E3D]' : 'text-[#A65D57]',
                    )}
                >
                    {formatDate(line.date).slice(0, 5)}
                </span>

                <div className={cn('min-w-0 flex-1', dim && 'opacity-60')}>
                    <input
                        value={row.name}
                        onChange={(e) => onChange({ name: e.target.value })}
                        className="w-full rounded-lg border border-transparent bg-transparent px-2 py-1 font-bold text-[#3D2817] hover:border-[#E8DCC4] focus:border-[#6B4E3D] focus:outline-none"
                        aria-label="Nome"
                    />
                    <p className="truncate px-2 text-xs text-[#8B7355]">
                        {line.description}
                        {line.last4 && ` · final ${line.last4}`}
                        {line.suggestion.learned && (
                            <span className="ml-1 inline-flex items-center gap-0.5 text-[#6B4E3D]">
                                <Sparkles className="h-3 w-3" /> lembrado
                            </span>
                        )}
                    </p>
                </div>

                <select
                    value={row.category_id}
                    onChange={(e) => onChange({ category_id: e.target.value })}
                    className={cn(
                        'w-full rounded-xl border-2 bg-white px-2 py-1.5 text-sm text-[#3D2817] md:w-44',
                        error && !row.category_id && row.launch
                            ? 'border-[#A65D57]'
                            : 'border-[#E8DCC4]',
                        dim && 'opacity-60',
                    )}
                    aria-label="Categoria"
                >
                    <option value="">Categoria…</option>
                    {categories.map((c) => (
                        <option key={c.id} value={c.id}>
                            {c.name}
                        </option>
                    ))}
                </select>

                <span
                    className={cn(
                        'w-24 shrink-0 text-right font-bold',
                        credit ? 'text-[#1F5428]' : 'text-[#3D2817]',
                        dim && 'opacity-60',
                    )}
                >
                    {credit ? '+' : ''}
                    {formatCurrency(row.amount)}
                </span>

                <button
                    type="button"
                    onClick={onToggleOpen}
                    className="rounded-lg p-1 text-[#8B7355] hover:bg-[#F5EFE6]"
                    aria-label="Mais opções"
                    aria-expanded={open}
                >
                    <ChevronDown
                        className={cn(
                            'h-5 w-5 transition-transform',
                            open && 'rotate-180',
                        )}
                    />
                </button>
            </div>

            {/* Avisos */}
            <div className="mt-1 flex flex-wrap gap-1.5 pl-8">
                {line.match && (
                    <Badge
                        tone={line.match.confidence === 'exact' ? 'ok' : 'warn'}
                    >
                        <Link2 className="h-3 w-3" />
                        {matched
                            .map(
                                (m) =>
                                    `${m.name} (${formatDate(m.date).slice(0, 5)} · ${formatCurrency(m.amount)})`,
                            )
                            .join(', ')}
                        {' — '}
                        {CONFIDENCE_LABEL[line.match.confidence]}
                        {line.match.confidence === 'combined' &&
                            ` (${line.match.group.length} linhas)`}
                        {row.launch && ' · vai lançar mesmo assim'}
                    </Badge>
                )}
                {line.deduction > 0 && (
                    <Badge tone="info">
                        {formatCurrency(line.amount)} − estorno{' '}
                        {formatCurrency(line.deduction)}
                    </Badge>
                )}
                {line.outside_period && (
                    <Badge tone="info">
                        compra de {formatDate(line.date).slice(0, 5)}: entra na
                        fatura em {formatDate(line.launch_date).slice(0, 5)}
                    </Badge>
                )}
                {!line.date_ok && (
                    <Badge tone="warn">data ilegível — confira</Badge>
                )}
                {line.corrected && (
                    <Badge tone="info">corrigido pelo total do banco</Badge>
                )}
                {line.uncertain && (
                    <Badge tone="warn">
                        valor incerto:
                        {line.candidates.map((c) => (
                            <button
                                key={c}
                                type="button"
                                onClick={() =>
                                    onChange({ amount: Math.abs(c) })
                                }
                                className={cn(
                                    'rounded px-1 underline',
                                    Math.abs(c) === row.amount &&
                                        'bg-[#3D2817] text-white no-underline',
                                )}
                            >
                                {formatCurrency(Math.abs(c))}
                            </button>
                        ))}
                    </Badge>
                )}
                {credit && <Badge tone="info">crédito (abate da fatura)</Badge>}
                {row.split && (
                    <Badge tone="info">
                        {row.split === 'half'
                            ? 'dividida'
                            : 'para outra pessoa'}
                    </Badge>
                )}
            </div>

            {error && (
                <p className="mt-1 pl-8 text-xs text-[#A65D57]">{error}</p>
            )}

            {open && (
                <div className="mt-3 grid gap-3 border-t border-[#F5EFE6] pt-3 pl-8 md:grid-cols-2">
                    <div>
                        <p className="mb-1 text-xs font-bold text-[#8B7355] uppercase">
                            Tags
                        </p>
                        <TagInput
                            value={row.tags}
                            onChange={(tags) => onChange({ tags })}
                        />
                    </div>
                    {!credit && (
                        <div>
                            <p className="mb-1 text-xs font-bold text-[#8B7355] uppercase">
                                Divisão
                            </p>
                            <select
                                value={row.split}
                                onChange={(e) =>
                                    onChange({ split: e.target.value as Split })
                                }
                                className={cn(inputClass, 'mb-2')}
                            >
                                <option value="">Só minha</option>
                                <option value="half">Metade com…</option>
                                <option value="theirs">
                                    Compra para outra pessoa (a receber)
                                </option>
                            </select>
                            {row.split && (
                                <select
                                    value={row.contact}
                                    onChange={(e) =>
                                        onChange({ contact: e.target.value })
                                    }
                                    className={inputClass}
                                >
                                    <option value="">Quem?</option>
                                    {contacts.map((c) => (
                                        <option key={c.id} value={c.id}>
                                            {c.name}
                                        </option>
                                    ))}
                                </select>
                            )}
                        </div>
                    )}
                    <p className="text-xs text-[#8B7355] md:col-span-2">
                        No extrato:{' '}
                        <span className="font-mono">{line.raw}</span>
                    </p>
                </div>
            )}
        </li>
    );
}

function IgnoredRow({ line, pair }: { line: ImportLine; pair?: ImportLine }) {
    return (
        <li className="flex items-center gap-3 rounded-2xl border border-[#E8DCC4] bg-[#FBF7F1] p-3 opacity-80">
            <span className="w-12 shrink-0 text-sm font-bold text-[#8B7355]">
                {formatDate(line.date).slice(0, 5)}
            </span>
            <div className="min-w-0 flex-1">
                <p className="truncate font-bold text-[#6B4E3D]">
                    {line.description}
                </p>
                <p className="text-xs text-[#8B7355]">
                    {KIND_LABEL[line.kind]}
                    {pair &&
                        line.kind === 'deducted' &&
                        ` (${pair.description})`}
                </p>
            </div>
            <span className="text-sm font-bold text-[#6B4E3D]">
                {formatCurrency(line.amount)}
            </span>
        </li>
    );
}

function ExistingPanel({ review }: { review: ImportReview }) {
    const inInvoice = review.existing.filter((e) => e.in_invoice);
    const around = review.existing.filter(
        (e) => !e.in_invoice && e.matched_lines.length > 0,
    );

    return (
        <div className="rounded-3xl border border-[#E8DCC4] bg-[#FBF7F1] p-5">
            <p className="mb-1 font-bold text-[#3D2817] capitalize">
                Já na fatura de {formatMonth(review.reference)}
            </p>
            <p className="mb-3 text-xs text-[#8B7355]">
                {formatDate(review.period.start).slice(0, 5)} a{' '}
                {formatDate(review.period.closing).slice(0, 5)} · vence{' '}
                {formatDate(review.period.due)}
            </p>

            {inInvoice.length === 0 ? (
                <p className="text-sm text-[#8B7355]">
                    Nada cadastrado nesta fatura ainda.
                </p>
            ) : (
                <ul className="max-h-[50vh] space-y-1.5 overflow-y-auto pr-1">
                    {inInvoice.map((e) => (
                        <ExistingItem key={e.id} item={e} />
                    ))}
                </ul>
            )}

            {around.length > 0 && (
                <>
                    <p className="mt-4 mb-2 text-xs font-bold tracking-wider text-[#8B7355] uppercase">
                        Em outras faturas
                    </p>
                    <ul className="space-y-1.5">
                        {around.map((e) => (
                            <ExistingItem key={e.id} item={e} />
                        ))}
                    </ul>
                </>
            )}
        </div>
    );
}

function ExistingItem({ item }: { item: ImportExisting }) {
    const found = item.matched_lines.length > 0;

    return (
        <li className="flex items-center gap-2 text-sm">
            {item.category ? (
                <CategoryIcon
                    category={item.category}
                    className="h-7 w-7 shrink-0"
                />
            ) : (
                <span className="h-7 w-7 shrink-0" />
            )}
            <div className="min-w-0 flex-1">
                <p className="truncate font-bold text-[#3D2817]">
                    {item.name}
                    {item.installment && (
                        <span className="ml-1 text-xs font-normal text-[#8B7355]">
                            {item.installment}
                        </span>
                    )}
                </p>
                <p className="text-xs text-[#8B7355]">
                    {formatDate(item.date).slice(0, 5)}
                    {!item.in_invoice &&
                        item.invoice_reference &&
                        ` · fatura de ${formatMonth(item.invoice_reference)}`}
                    {found
                        ? ' · no extrato'
                        : item.in_invoice
                          ? ' · não está no extrato'
                          : ''}
                </p>
            </div>
            <span
                className={cn(
                    'font-bold',
                    item.type === 'income'
                        ? 'text-[#1F5428]'
                        : 'text-[#3D2817]',
                )}
            >
                {formatCurrency(item.amount)}
            </span>
            {found || item.reconciled ? (
                <Check
                    className="h-4 w-4 shrink-0 text-[#1F5428]"
                    aria-label="Conferida"
                />
            ) : (
                <span className="h-4 w-4 shrink-0" />
            )}
        </li>
    );
}

function Badge({
    tone,
    children,
}: {
    tone: 'ok' | 'warn' | 'info';
    children: ReactNode;
}) {
    return (
        <span
            className={cn(
                'inline-flex flex-wrap items-center gap-1 rounded-full px-2 py-0.5 text-xs',
                tone === 'ok' && 'bg-[#E3F9E5] text-[#1F5428]',
                tone === 'warn' && 'bg-[#FFF4D6] text-[#8A6100]',
                tone === 'info' && 'bg-[#F5EFE6] text-[#6B4E3D]',
            )}
        >
            {children}
        </span>
    );
}
