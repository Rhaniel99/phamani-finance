<?php

namespace App\Http\Controllers;

use App\DTOs\Account\StoreAccountData;
use App\DTOs\Account\UpdateAccountData;
use App\Interfaces\Services\IAccountService;
use App\Models\Account;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;

class AccountController extends Controller
{
    public function __construct(
        protected IAccountService $service,
    ) {}

    public function store(Request $request, StoreAccountData $data): RedirectResponse
    {
        $this->service->create((string) $request->user()?->getAuthIdentifier(), $data);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Conta criada com sucesso!']);

        return back();
    }

    public function update(Request $request, Account $account, UpdateAccountData $data): RedirectResponse
    {
        abort_unless($account->user_id === (string) $request->user()?->getAuthIdentifier(), 404);

        $this->service->update($account, $data);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Conta atualizada!']);

        return back();
    }

    /**
     * Impacto da exclusão, para a confirmação (JSON).
     */
    public function impact(Request $request, Account $account): JsonResponse
    {
        abort_unless($account->user_id === (string) $request->user()?->getAuthIdentifier(), 404);

        return response()->json($this->service->deletionImpact($account));
    }

    public function destroy(Request $request, Account $account): RedirectResponse
    {
        abort_unless($account->user_id === (string) $request->user()?->getAuthIdentifier(), 404);

        $request->validate(['confirm' => ['required', 'string']]);

        // Confirmação digitada: o nome da conta.
        if (mb_strtolower(trim((string) $request->input('confirm'))) !== mb_strtolower(trim($account->name))) {
            return back()->withErrors(['confirm' => 'Digite o nome da conta exatamente como está.']);
        }

        $name = $account->name;
        $this->service->delete($account);

        Inertia::flash('toast', ['type' => 'success', 'message' => "\"{$name}\" foi excluída."]);

        // Saindo da página do próprio cartão (que não existe mais): vai para o painel.
        $previous = url()->previous();

        return str_contains($previous, '/cards/'.$account->id)
            ? redirect()->route('dashboard')
            : back();
    }
}
