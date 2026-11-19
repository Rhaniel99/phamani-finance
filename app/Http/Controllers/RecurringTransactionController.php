<?php

namespace App\Http\Controllers;

use App\Interfaces\Services\IRecurringTransactionService;
use App\Models\RecurringTransaction;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;

class RecurringTransactionController extends Controller
{
    public function __construct(
        protected IRecurringTransactionService $service,
    ) {}

    /**
     * Encerra a recorrência: as ocorrências já lançadas ficam, nenhuma nova é criada.
     */
    public function end(Request $request, RecurringTransaction $recurring): RedirectResponse
    {
        // 404 (e não 403) para não revelar que a recorrência de outro usuário existe.
        abort_unless($recurring->user_id === (string) $request->user()?->getAuthIdentifier(), 404);

        $this->service->end($recurring);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Recorrência encerrada.']);

        return back();
    }
}
