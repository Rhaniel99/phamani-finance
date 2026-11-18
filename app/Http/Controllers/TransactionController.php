<?php

namespace App\Http\Controllers;

use App\DTOs\Transaction\StoreTransactionData;
use App\DTOs\Transaction\UpdateTransactionData;
use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\ITransactionService;
use App\Models\Transaction;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

class TransactionController extends Controller
{
    public function __construct(
        protected ITransactionService $service,
        protected IAccountService $accountService,
        protected ICategoryService $categoryService,
    ) {}

    public function index(Request $request): Response
    {
        $userId = (string) $request->user()?->getAuthIdentifier();

        $filters = $request->validate([
            'account_id' => ['nullable', 'uuid'],
            'category_id' => ['nullable', 'uuid'],
            'type' => ['nullable', Rule::in(['income', 'expense'])],
            'month' => ['nullable', 'date_format:Y-m'],
        ]);

        return Inertia::render('transactions/index', [
            'filters' => (object) array_filter($filters),
            'transactions' => fn () => $this->service->paginateForUser($userId, $filters),
            'accounts' => fn () => $this->accountService->listForUser($userId),
            'categories' => fn () => $this->categoryService->listForUser($userId),
        ]);
    }

    public function store(Request $request, StoreTransactionData $data): RedirectResponse
    {
        $this->service->create((string) $request->user()?->getAuthIdentifier(), $data);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Transação criada com sucesso!']);

        return back();
    }

    public function update(Request $request, Transaction $transaction, UpdateTransactionData $data): RedirectResponse
    {
        $this->ensureOwner($request, $transaction);

        $this->service->update($transaction, $data);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Transação atualizada!']);

        return back();
    }

    public function destroy(Request $request, Transaction $transaction): RedirectResponse
    {
        $this->ensureOwner($request, $transaction);

        $isInstallment = $transaction->installment_id !== null;

        $this->service->delete($transaction);

        Inertia::flash('toast', [
            'type' => 'success',
            'message' => $isInstallment ? 'Parcelamento excluído.' : 'Transação excluída.',
        ]);

        return back();
    }

    /**
     * Responde 404 (e não 403) para não revelar que a transação de outro usuário existe.
     */
    private function ensureOwner(Request $request, Transaction $transaction): void
    {
        abort_unless($transaction->user_id === (string) $request->user()?->getAuthIdentifier(), 404);
    }
}
