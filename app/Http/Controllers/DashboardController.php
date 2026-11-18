<?php

namespace App\Http\Controllers;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\IDashboardService;
use App\Interfaces\Services\ITransactionService;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

class DashboardController extends Controller
{
    public function __construct(
        protected IAccountService $accountService,
        protected ICategoryService $categoryService,
        protected IDashboardService $dashboardService,
        protected ITransactionService $transactionService,
    ) {}

    public function __invoke(Request $request): Response
    {
        $userId = (string) $request->user()?->getAuthIdentifier();

        $period = $request->validate([
            'period' => ['nullable', Rule::in(['monthly', 'yearly'])],
        ])['period'] ?? 'yearly';

        return Inertia::render('dashboard', [
            'period' => $period,
            'kpis' => fn () => $this->dashboardService->kpis($userId),
            'cashFlow' => fn () => $this->dashboardService->cashFlow($userId, $period),
            'categoryPie' => fn () => $this->dashboardService->categoryPie($userId, $period),
            'recentTransactions' => fn () => $this->transactionService->getRecentForDashboard($userId),
            'accounts' => fn () => $this->accountService->listForUser($userId),
            'categories' => fn () => $this->categoryService->listForUser($userId),
        ]);
    }
}
