<?php

namespace App\Http\Controllers;

use App\DTOs\CreditCard\PayInvoiceData;
use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\ICreditCardService;
use App\Models\Account;
use App\Models\CreditCardInvoice;
use App\Models\Transaction;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

class CreditCardController extends Controller
{
    public function __construct(
        protected ICreditCardService $cards,
        protected IAccountService $accountService,
        protected ICategoryService $categoryService,
    ) {}

    /**
     * Página do cartão: limite, faturas e as compras da fatura selecionada.
     */
    public function show(Request $request, Account $account): Response
    {
        $userId = $this->ensureOwner($request, $account->user_id);
        abort_unless($account->isCreditCard(), 404);

        $invoices = $this->cards->invoicesFor($account);
        $summary = $this->cards->summary($account);

        // Seleção: ?invoice=… ou a fatura atual (ou a mais recente, se a atual ainda não existir).
        $selectedId = $request->string('invoice')->toString()
            ?: ($summary['current_invoice']['id'] ?? null)
            ?: ($invoices[0]['id'] ?? null);

        $selected = collect($invoices)->firstWhere('id', $selectedId);

        return Inertia::render('cards/show', [
            'card' => [
                ...$account->only(['id', 'name', 'type', 'credit_limit', 'closing_day', 'due_day', 'payment_account_id']),
                'card' => $summary,
            ],
            'invoices' => $invoices,
            'selectedInvoice' => $selected,
            'transactions' => fn () => $selected === null ? [] : Transaction::query()
                ->where('user_id', $userId)
                ->where('invoice_id', $selected['id'])
                ->with([
                    'account:id,name,type',
                    'category:id,name,color,icon',
                'splits:id,transaction_id,contact_id,amount',
                'splits.contact:id,name',
                'paidBy:id,name,linked_user_id',
                'mirroredFrom:id,user_id,total_amount,paid_by_contact_id',
                'mirroredFrom.user:id,name,avatar',
                'mirroredFrom.paidBy:id,name,linked_user_id',
                'mirroredFrom.splits:id,transaction_id,contact_id,amount',
                'mirroredFrom.splits.contact:id,name,linked_user_id',
                'shareLinks:id,share_id,source_transaction_id,mirror_transaction_id',
                'shareLinks.share:id,status,owner_contact_id',
                    'recurring:id,frequency,end_date,auto_pay',
                    'installment:id,name,installments,installment_amount,total_amount,auto_pay',
                    'installment.transactions:id,installment_id,installment_number,date,amount',
                ])
                ->orderByDesc('date')
                ->orderByDesc('created_at')
                ->get(),
            'accounts' => fn () => $this->accountService->listForUser($userId),
            'categories' => fn () => $this->categoryService->listForUser($userId),
        ]);
    }

    public function pay(Request $request, CreditCardInvoice $invoice, PayInvoiceData $data): RedirectResponse
    {
        $this->ensureOwner($request, $invoice->user_id);

        $this->cards->pay($invoice, $data->account_id, $data->date);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Fatura paga!']);

        return back();
    }

    public function undo(Request $request, CreditCardInvoice $invoice): RedirectResponse
    {
        $this->ensureOwner($request, $invoice->user_id);

        $this->cards->undoPayment($invoice);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Pagamento desfeito.']);

        return back();
    }

    /**
     * 404 (e não 403) para não revelar que o recurso de outro usuário existe.
     */
    private function ensureOwner(Request $request, string $ownerId): string
    {
        $userId = (string) $request->user()?->getAuthIdentifier();

        abort_unless($ownerId === $userId, 404);

        return $userId;
    }
}
