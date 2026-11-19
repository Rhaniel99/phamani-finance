/**
 * Valor de cada parcela.
 * - mode 'installment': o valor digitado já é o da parcela;
 * - mode 'total': o valor digitado é o da compra inteira, dividido por `count`
 *   (mesmo começando de uma parcela > 1: "R$ 625 em 4x" = R$ 156,25 cada).
 */
export function getInstallmentValue(
    amount?: number,
    count?: number,
    _start = 1,
    mode: 'total' | 'installment' = 'total',
): number | null {
    if (!amount || !count) return null;

    if (mode === 'installment') return amount;

    return Math.floor((amount / count) * 100) / 100;
}
