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
}
