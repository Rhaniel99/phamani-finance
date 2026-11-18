<?php

namespace App\Interfaces\Services;

interface IDashboardService
{
    /** @return array<string, mixed> */
    public function kpis(string $userId): array;

    /** @return list<array{label: string, income: float, expense: float}> */
    public function cashFlow(string $userId, string $period = 'yearly'): array;

    /** @return list<array{name: string, value: float, color: string}> */
    public function categoryPie(string $userId, string $period = 'monthly'): array;
}
