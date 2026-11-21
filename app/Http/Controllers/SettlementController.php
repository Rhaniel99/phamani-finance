<?php

namespace App\Http\Controllers;

use App\Interfaces\Services\IReimbursementService;
use App\Models\Settlement;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;

/**
 * Acerto entre usuários: quem deve informa o pagamento, quem recebe confirma ou recusa.
 */
class SettlementController extends Controller
{
    public function __construct(
        protected IReimbursementService $reimbursements,
    ) {}

    /** "Paguei": quem deve informa o pagamento de itens do acerto para $creditor. */
    public function pay(Request $request, User $creditor): RedirectResponse
    {
        $data = $request->validate([
            'split_ids' => ['required', 'array', 'min:1'],
            'split_ids.*' => ['uuid'],
            'account_id' => ['required', 'uuid'],
            'date' => ['required', 'date'],
        ]);

        $this->reimbursements->pay($this->user($request), $creditor, array_values($data['split_ids']), $data['account_id'], $data['date']);

        Inertia::flash('toast', ['type' => 'success', 'message' => "Pagamento informado. Aguardando {$creditor->name} confirmar."]);

        return back();
    }

    public function confirm(Request $request, Settlement $settlement): RedirectResponse
    {
        $data = $request->validate(['to_account_id' => ['required', 'uuid']]);

        $this->reimbursements->confirm($this->user($request), $settlement, $data['to_account_id']);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Recebimento confirmado.']);

        return back();
    }

    public function reject(Request $request, Settlement $settlement): RedirectResponse
    {
        $this->reimbursements->reject($this->user($request), $settlement);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Pagamento recusado: voltou para "a pagar".']);

        return back();
    }

    public function cancel(Request $request, Settlement $settlement): RedirectResponse
    {
        $this->reimbursements->cancel($this->user($request), $settlement);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Pagamento cancelado.']);

        return back();
    }

    private function user(Request $request): User
    {
        /** @var User */
        return $request->user();
    }
}
