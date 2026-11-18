<?php

namespace App\Http\Controllers;

use App\DTOs\Account\StoreAccountData;
use App\Interfaces\Services\IAccountService;
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
}
