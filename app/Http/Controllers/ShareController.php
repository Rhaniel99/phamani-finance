<?php

namespace App\Http\Controllers;

use App\DTOs\Sharing\AcceptShareData;
use App\Interfaces\Services\IShareService;
use App\Models\Share;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;

class ShareController extends Controller
{
    public function __construct(
        protected IShareService $service,
    ) {}

    public function accept(Request $request, Share $share, AcceptShareData $data): RedirectResponse
    {
        $this->service->accept($share, $this->user($request), $data->category_id, $data->account_id);

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Divisão aceita! Sua parte já está nas suas transações.']);

        return back();
    }

    public function decline(Request $request, Share $share): RedirectResponse
    {
        $this->service->decline($share, $this->user($request));

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Divisão recusada.']);

        return back();
    }

    public function leave(Request $request, Share $share): RedirectResponse
    {
        $this->service->leave($share, $this->user($request));

        Inertia::flash('toast', ['type' => 'success', 'message' => 'Você saiu da divisão.']);

        return back();
    }

    private function user(Request $request): User
    {
        /** @var User */
        return $request->user();
    }
}
