<?php

namespace App\Http\Controllers;

use App\DTOs\Account\StoreAccountData;
use App\DTOs\Account\UpdateAccountData;
use App\Interfaces\Services\IAccountService;
use App\Models\Account;
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
}
