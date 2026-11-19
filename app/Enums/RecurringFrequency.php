<?php

namespace App\Enums;

use Carbon\CarbonInterface;

enum RecurringFrequency: string
{
    case DAILY = 'daily';
    case WEEKLY = 'weekly';
    case MONTHLY = 'monthly';
    case YEARLY = 'yearly';

    public function label(): string
    {
        return match ($this) {
            self::DAILY => 'Diário',
            self::WEEKLY => 'Semanal',
            self::MONTHLY => 'Mensal',
            self::YEARLY => 'Anual',
        };
    }

    /**
     * Calcula a próxima ocorrência a partir de uma data base.
     */
    public function nextAfter(CarbonInterface $date): CarbonInterface
    {
        return match ($this) {
            self::DAILY => $date->addDay(),
            self::WEEKLY => $date->addWeek(),
            self::MONTHLY => $date->addMonthNoOverflow(),
            self::YEARLY => $date->addYearNoOverflow(),
        };
    }

    /**
     * N-ésima ocorrência depois da âncora (n = 1 é a seguinte à âncora).
     * Calcular sempre a partir da âncora evita que o dia "escorregue":
     * 31/01 → 28/02 → 31/03 (e não 28/03).
     */
    public function nth(CarbonInterface $anchor, int $n): CarbonInterface
    {
        $anchor = $anchor->toImmutable();

        return match ($this) {
            self::DAILY => $anchor->addDays($n),
            self::WEEKLY => $anchor->addWeeks($n),
            self::MONTHLY => $anchor->addMonthsNoOverflow($n),
            self::YEARLY => $anchor->addYearsNoOverflow($n),
        };
    }

    /**
     * Primeira ocorrência estritamente depois de $after, a partir da âncora.
     */
    public function nextFromAnchor(CarbonInterface $anchor, CarbonInterface $after): CarbonInterface
    {
        $n = 1;

        while ($this->nth($anchor, $n)->toDateString() <= $after->toDateString()) {
            $n++;
        }

        return $this->nth($anchor, $n);
    }
}
