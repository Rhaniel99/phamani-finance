<?php

namespace App\Support;

use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;

/**
 * Calendário do acerto do mês.
 *
 * O acerto de um mês é pago até o 5º dia útil desse mês (quando cai o salário). Entra nele:
 * - compra no cartão: a fatura que vence nesse mês;
 * - o resto: a data do lançamento.
 *
 * Dia útil: segunda a sexta, menos feriados nacionais (fixos + Carnaval, Sexta-feira Santa e Corpus Christi).
 */
final class Acerto
{
    public const int BUSINESS_DAY = 5;

    /** Mês do acerto (YYYY-MM) de um lançamento. */
    public static function monthOf(CarbonInterface $date, ?CarbonInterface $invoiceDueDate = null): string
    {
        return ($invoiceDueDate ?? $date)->format('Y-m');
    }

    /** Prazo do acerto de um mês: o 5º dia útil. */
    public static function deadline(string $month): CarbonImmutable
    {
        $day = CarbonImmutable::createFromFormat('!Y-m', $month)->startOfMonth();
        $count = 0;

        while (true) {
            if (self::isBusinessDay($day) && ++$count === self::BUSINESS_DAY) {
                return $day;
            }
            $day = $day->addDay();
        }
    }

    /**
     * O acerto "da vez": o deste mês até o prazo; passado o prazo, o do mês seguinte.
     */
    public static function current(?CarbonInterface $today = null): string
    {
        $today = CarbonImmutable::instance($today ?? now())->startOfDay();
        $month = $today->format('Y-m');

        return $today->greaterThan(self::deadline($month))
            ? $today->startOfMonth()->addMonthNoOverflow()->format('Y-m')
            : $month;
    }

    /** overdue (acerto que já passou), current (o da vez) ou upcoming (meses seguintes). */
    public static function group(string $month, ?string $current = null): string
    {
        $current ??= self::current();

        return match (true) {
            $month < $current => 'overdue',
            $month === $current => 'current',
            default => 'upcoming',
        };
    }

    public static function isBusinessDay(CarbonInterface $day): bool
    {
        return ! $day->isWeekend() && ! in_array($day->format('m-d'), self::holidays((int) $day->format('Y')), true);
    }

    /**
     * Feriados nacionais (m-d) do ano.
     *
     * @return list<string>
     */
    private static function holidays(int $year): array
    {
        $easter = self::easter($year);

        return [
            '01-01', '04-21', '05-01', '09-07', '10-12', '11-02', '11-15', '11-20', '12-25',
            $easter->subDays(48)->format('m-d'), // Carnaval (segunda)
            $easter->subDays(47)->format('m-d'), // Carnaval (terça)
            $easter->subDays(2)->format('m-d'),  // Sexta-feira Santa
            $easter->addDays(60)->format('m-d'), // Corpus Christi
        ];
    }

    /** Domingo de Páscoa (algoritmo de Meeus/Jones/Butcher). */
    private static function easter(int $year): CarbonImmutable
    {
        $a = $year % 19;
        $b = intdiv($year, 100);
        $c = $year % 100;
        $d = intdiv($b, 4);
        $e = $b % 4;
        $f = intdiv($b + 8, 25);
        $g = intdiv($b - $f + 1, 3);
        $h = (19 * $a + $b - $d - $g + 15) % 30;
        $i = intdiv($c, 4);
        $k = $c % 4;
        $l = (32 + 2 * $e + 2 * $i - $h - $k) % 7;
        $m = intdiv($a + 11 * $h + 22 * $l, 451);
        $month = intdiv($h + $l - 7 * $m + 114, 31);
        $day = (($h + $l - 7 * $m + 114) % 31) + 1;

        return CarbonImmutable::create($year, $month, $day);
    }
}
