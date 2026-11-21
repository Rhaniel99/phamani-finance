<?php

namespace App\Http\Controllers;

use App\Interfaces\Services\IReimbursementService;
use App\Models\Contact;
use App\Models\TransactionSplit;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;

/**
 * Compra para outra pessoa: registrar (ou desfazer) o reembolso.
 */
class ReimbursementController extends Controller
{
    public function __construct(
        protected IReimbursementService $reimbursements,
    ) {}

    public function receive(Request $request, Contact $contact): RedirectResponse
    {
        $data = $request->validate([
            'split_ids' => ['required', 'array', 'min:1'],
            'split_ids.*' => ['uuid'],
            'account_id' => ['required', 'uuid'],
            'date' => ['required', 'date'],
        ]);

        /** @var User $user */
        $user = $request->user();

        $this->reimbursements->receive($user, $contact, array_values($data['split_ids']), $data['account_id'], $data['date']);

        Inertia::flash('toast', ['type' => 'success', 'message' => "Recebimento de {$contact->name} registrado."]);

        return back();
    }

    public function undo(Request $request, TransactionSplit $split): RedirectResponse
    {
        /** @var User $user */
        $user = $request->user();

        $this->reimbursements->undo($user, $split);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Recebimento desfeito.']);

        return back();
    }
}
