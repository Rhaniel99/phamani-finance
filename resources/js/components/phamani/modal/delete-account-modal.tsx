import { router } from '@inertiajs/react';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Button } from '@/components/phamani/ui/button';
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog';
import { formatCurrency } from '@/lib/format';
import { destroy, impact as impactRoute } from '@/routes/accounts';
import type { Account } from '@/types/phamani';

interface Impact {
    transactions: number;
    installments: number;
    recurring: number;
    invoices: number;
    paid_invoices: number;
    shared: number;
    mirrors: number;
    balance: number;
    is_last: boolean;
}

interface DeleteAccountModalProps {
    account: Account;
    isOpen: boolean;
    onClose: () => void;
    /** Chamado depois de excluir (ex.: fechar o drawer de edição). */
    onDeleted?: () => void;
}

function plural(n: number, one: string, many: string) {
    return `${n} ${n === 1 ? one : many}`;
}

/**
 * Exclusão definitiva de conta/cartão: mostra o que some junto e pede o nome da conta.
 */
export function DeleteAccountModal({
    account,
    isOpen,
    onClose,
    onDeleted,
}: DeleteAccountModalProps) {
    const [impact, setImpact] = useState<Impact | null>(null);
    const [confirm, setConfirm] = useState('');
    const [error, setError] = useState<string | null>(null);
    const [processing, setProcessing] = useState(false);

    useEffect(() => {
        if (!isOpen) return;
        setImpact(null);
        setConfirm('');
        setError(null);

        let cancelled = false;
        fetch(impactRoute.url(account.id), {
            headers: { Accept: 'application/json' },
            credentials: 'same-origin',
        })
            .then((r) => (r.ok ? r.json() : Promise.reject(r)))
            .then((data: Impact) => !cancelled && setImpact(data))
            .catch(
                () =>
                    !cancelled &&
                    setError('Não consegui calcular o impacto. Tente de novo.'),
            );

        return () => {
            cancelled = true;
        };
    }, [isOpen, account.id]);

    const isCard = account.type === 'credit';
    const matches =
        confirm.trim().toLowerCase() === account.name.trim().toLowerCase();

    function submit() {
        router.delete(destroy.url(account.id), {
            data: { confirm },
            preserveScroll: true,
            onStart: () => setProcessing(true),
            onFinish: () => setProcessing(false),
            onError: (e) =>
                setError(e.confirm ?? e.account ?? 'Não foi possível excluir.'),
            onSuccess: () => {
                onClose();
                onDeleted?.();
            },
        });
    }

    const items: string[] = impact
        ? [
              impact.transactions > 0 &&
                  plural(impact.transactions, 'transação', 'transações') +
                      (impact.installments > 0
                          ? ` (incluindo ${plural(impact.installments, 'parcelamento inteiro', 'parcelamentos inteiros')})`
                          : ''),
              impact.recurring > 0 &&
                  plural(impact.recurring, 'recorrência', 'recorrências') +
                      ' (param de gerar lançamentos)',
              impact.invoices > 0 &&
                  plural(impact.invoices, 'fatura', 'faturas') +
                      (impact.paid_invoices > 0
                          ? `, ${impact.paid_invoices} já paga${impact.paid_invoices === 1 ? '' : 's'} (o dinheiro que saiu da conta de pagamento continua descontado)`
                          : ''),
              impact.shared > 0 &&
                  plural(
                      impact.shared,
                      'compra dividida',
                      'compras divididas',
                  ) +
                      ': a divisão, o acerto e reembolsos recebidos são desfeitos',
          ].filter((x): x is string => typeof x === 'string')
        : [];

    return (
        <Dialog open={isOpen} onOpenChange={(open) => !open && onClose()}>
            <DialogContent className="max-w-lg rounded-3xl border-[#E8DCC4] bg-[#F5EFE6]">
                <DialogHeader>
                    <DialogTitle className="flex items-center gap-2 text-2xl text-[#A65D57]">
                        <AlertTriangle className="h-6 w-6" />
                        Excluir {isCard ? 'cartão' : 'conta'}
                    </DialogTitle>
                    <DialogDescription className="text-[#6B4E3D]">
                        <strong>{account.name}</strong> será excluíd
                        {isCard ? 'o' : 'a'} de vez, com tudo que é del
                        {isCard ? 'e' : 'a'}. Não dá para desfazer.
                    </DialogDescription>
                </DialogHeader>

                {!impact && !error && (
                    <div className="flex items-center gap-2 text-sm text-[#8B7355]">
                        <Loader2 className="h-4 w-4 animate-spin" /> Calculando
                        o que será apagado…
                    </div>
                )}

                {impact?.is_last && (
                    <p className="rounded-2xl bg-[#FCE7E7] p-4 text-sm text-[#A65D57]">
                        Esta é sua única conta (fora os cartões). Crie outra
                        antes de excluir.
                    </p>
                )}

                {impact && !impact.is_last && (
                    <div className="space-y-3 rounded-2xl border border-[#E8DCC4] bg-white p-4 text-sm text-[#3D2817]">
                        {items.length === 0 ? (
                            <p>
                                Não tem nenhum lançamento: nada além d
                                {isCard ? 'o cartão' : 'a conta'} será apagado.
                            </p>
                        ) : (
                            <>
                                <p className="font-bold">
                                    Também serão apagados:
                                </p>
                                <ul className="list-disc space-y-1 pl-5">
                                    {items.map((item) => (
                                        <li key={item}>{item}</li>
                                    ))}
                                </ul>
                            </>
                        )}
                        {!isCard && impact.balance !== 0 && (
                            <p className="text-[#A65D57]">
                                O saldo de {formatCurrency(impact.balance)}{' '}
                                deixa de contar no seu total.
                            </p>
                        )}
                        {impact.mirrors > 0 && (
                            <p className="text-[#6B4E3D]">
                                {plural(
                                    impact.mirrors,
                                    'compra de outra pessoa dividida com você continua',
                                    'compras de outras pessoas divididas com você continuam',
                                )}
                                , só que sem conta.
                            </p>
                        )}
                    </div>
                )}

                {impact && !impact.is_last && (
                    <div>
                        <label
                            htmlFor="confirm-account-name"
                            className="mb-1 block text-sm text-[#6B4E3D]"
                        >
                            Para confirmar, digite{' '}
                            <strong>{account.name}</strong>
                        </label>
                        <input
                            id="confirm-account-name"
                            value={confirm}
                            onChange={(e) => {
                                setConfirm(e.target.value);
                                setError(null);
                            }}
                            autoComplete="off"
                            className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-3 text-[#3D2817] focus:border-[#A65D57] focus:outline-none"
                        />
                    </div>
                )}

                {error && <p className="text-sm text-[#A65D57]">{error}</p>}

                <div className="flex justify-end gap-2">
                    <Button variant="secondary" onClick={onClose}>
                        Cancelar
                    </Button>
                    {impact && !impact.is_last && (
                        <button
                            type="button"
                            onClick={submit}
                            disabled={!matches || processing}
                            className="inline-flex items-center rounded-xl bg-[#A65D57] px-5 py-2.5 font-bold text-white transition-colors hover:bg-[#8C4A45] disabled:cursor-not-allowed disabled:opacity-40"
                        >
                            {processing && (
                                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                            )}
                            Excluir de vez
                        </button>
                    )}
                </div>
            </DialogContent>
        </Dialog>
    );
}
