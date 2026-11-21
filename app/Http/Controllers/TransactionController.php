<?php

namespace App\Http\Controllers;

use App\DTOs\Transaction\StoreTransactionData;
use App\DTOs\Transaction\UpdateTransactionData;
use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\IPaymentService;
use App\Interfaces\Services\ITransactionService;
use App\Models\Transaction;
use App\Models\User;
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
            'tag_id' => ['nullable', 'uuid'],
            'type' => ['nullable', Rule::in(['income', 'expense'])],
            'month' => ['nullable', 'date_format:Y-m'],
            'all' => ['nullable', 'boolean'],
            'search' => ['nullable', 'string', 'max:100'],
            'kind' => ['nullable', Rule::in(['split', 'installment', 'recurring', 'shared'])],
            'status' => ['nullable', Rule::in(['paid', 'pending', 'overdue'])],
        ]);

        // Padrão: um mês por vez (o atual). "Todo o período" só com all=1.
        $all = (bool) ($filters['all'] ?? false);
        if ($all) {
            unset($filters['month']);
        } else {
            $filters['month'] ??= now()->format('Y-m');
        }
        unset($filters['all']);

        return Inertia::render('transactions/index', [
            'filters' => (object) array_filter([...$filters, 'all' => $all ? '1' : null]),
            // Um mês cabe inteiro; "todo o período" vem em páginas de 50 ("carregar mais").
            'transactions' => fn () => $this->service->paginateForUser($userId, $filters, $all ? 50 : 500),
            'summary' => fn () => $all ? null : $this->service->summaryForUser($userId, $filters),
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

        if ($redirect = $this->rejectMirror($transaction)) {
            return $redirect;
        }

        $this->service->update($transaction, $data);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Transação atualizada!']);

        return back();
    }

    /**
     * Marca como paga (ou recebida). Só quem pagou pode marcar; vale para todos da divisão.
     */
    public function pay(Request $request, Transaction $transaction, IPaymentService $payments): RedirectResponse
    {
        $this->ensureOwner($request, $transaction);

        /** @var User $user */
        $user = $request->user();
        $payments->markPaid($transaction, $user);

        Inertia::flash('toast', [
            'type' => 'success',
            'message' => $transaction->type === 'income' ? 'Marcada como recebida.' : 'Marcada como paga.',
        ]);

        return back();
    }

    public function unpay(Request $request, Transaction $transaction, IPaymentService $payments): RedirectResponse
    {
        $this->ensureOwner($request, $transaction);

        /** @var User $user */
        $user = $request->user();
        $payments->markUnpaid($transaction, $user);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Voltou para pendente.']);

        return back();
    }

    public function destroy(Request $request, Transaction $transaction): RedirectResponse
    {
        $this->ensureOwner($request, $transaction);

        if ($redirect = $this->rejectMirror($transaction)) {
            return $redirect;
        }

        $isInstallment = $transaction->installment_id !== null;

        $this->service->delete($transaction);

        Inertia::flash('toast', [
            'type' => 'success',
            'message' => $isInstallment ? 'Parcelamento excluído.' : 'Transação excluída.',
        ]);

        return back();
    }

    /**
     * Cópia de divisão compartilhada: só quem criou edita. Quem recebeu pode sair da divisão em Pendências.
     */
    private function rejectMirror(Transaction $transaction): ?RedirectResponse
    {
        if (! $transaction->isMirror()) {
            return null;
        }

        Inertia::flash('toast', [
            'type' => 'error',
            'message' => 'Esta divisão foi compartilhada com você: só quem criou pode alterar. Você pode sair dela em Pendências.',
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
