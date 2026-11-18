export function getInstallmentValue(
    amount?: number,
    count?: number,
): number | null {
    if (!amount || !count) return null;

    return Math.floor((amount / count) * 100) / 100;
}
